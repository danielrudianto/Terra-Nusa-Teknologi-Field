import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/quiet.dart';
import '../../core/widgets/view_states.dart';
import '../../core/i18n.dart';
import 'daily_report_actions.dart';

/// Date range of the report, both ends included.
typedef ReportRange = ({DateTime from, DateTime to});

final _reportProvider = FutureProvider.autoDispose.family<Map<String, Object?>, ReportRange>(
  (ref, r) => ref.read(apiProvider).report(r.from, r.to),
);

/// What was drilled and cast, per project, for directors (level 5+) and
/// Engineering from level 3.
///
/// Read straight from the server (every phone's data), so it needs signal;
/// nothing of it is kept on the phone.
class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  /// today | yesterday | week | custom
  String _preset = 'today';

  /// The hand-picked range, both ends included.
  ///
  /// A RANGE, not a single day. It used to be one `DateTime`, so the only
  /// spans this page could show were today, yesterday and the last seven
  /// days — anything else, such as "the whole of October", had to be read
  /// one day at a time. Reported by Daniel, 10 November 2026.
  DateTimeRange? _customRange;

  /// Longest span the server accepts (`REKAP_HARI_MAKS` in
  /// `controllers/field_controller.py`).
  ///
  /// Held here as well so that picking too long a span is answered with a
  /// sentence that names the limit, instead of a 400 that reads "action
  /// failed". The server rejects `(to - from).days >= limit`, so the widest
  /// accepted span is this many days counting both ends.
  static const int _maxRangeDays = 400;

  /// An Excel download is running.
  bool _downloading = false;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  ReportRange get _range {
    final today = _day(DateTime.now());
    return switch (_preset) {
      'yesterday' => (from: today.subtract(const Duration(days: 1)), to: today.subtract(const Duration(days: 1))),
      'week' => (from: today.subtract(const Duration(days: 6)), to: today),
      'custom' when _customRange != null => (
        from: _day(_customRange!.start),
        to: _day(_customRange!.end),
      ),
      _ => (from: today, to: today),
    };
  }

  Future<void> _pickRange() async {
    final today = _day(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _customRange,
      firstDate: DateTime(2025),
      lastDate: today,
    );
    if (picked == null || !mounted) return;

    // Checked HERE, not left to the server. The figures on screen and the
    // download both use this range; letting an over-long one through means
    // the page loads, the numbers appear, and only the download fails — with
    // a message that does not say which part was wrong.
    final days = _day(picked.end).difference(_day(picked.start)).inDays + 1;
    if (days > _maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context).rangeTooLong('$_maxRangeDays'))),
      );
      return;
    }

    setState(() {
      _customRange = picked;
      _preset = 'custom';
    });
  }

  /// Label of the range chip: the chosen span, or the invitation to pick one.
  String _rangeChipLabel(BuildContext context) {
    final r = _customRange;
    if (_preset != 'custom' || r == null) return t(context).pickRange;
    final f = DateFormat('d MMM', 'id');
    return _day(r.start) == _day(r.end)
        ? f.format(r.start)
        : '${f.format(r.start)} – ${f.format(r.end)}';
  }

  /// Download "Rekapitulasi Data Tiang" (.xlsx, same layout as the file AKN
  /// sends clients) and hand it to the share sheet: open in a sheet app,
  /// or send by WhatsApp / e-mail.
  Future<void> _downloadExcel(ReportRange range) async {
    final choice = await showModalBottomSheet<_ExcelChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _ExcelOptionsSheet(range: range),
    );
    if (choice == null || !mounted) return;
    setState(() => _downloading = true);
    final subject = t(context).excelSubject;
    try {
      final from = choice.whole ? null : range.from;
      final bytes = await ref.read(apiProvider).reportExcel(from: from, to: range.to, sheets: choice.sheets);
      final name = 'Rekap-Tiang-${from == null ? 'lengkap' : isoDate(from)}_${isoDate(range.to)}.xlsx';
      final file = File('${(await getTemporaryDirectory()).path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          subject: subject,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(e is ApiError ? e.message : t(context).excelFailed('$e'))),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final range = _range;
    final report = ref.watch(_reportProvider(range));
    final projects = {
      for (final p in ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[]) '${p['id']}': p,
    };
    final multiDay = range.from != range.to;

    return Scaffold(
      appBar: AppBar(title: Text(t(context).reportsTitle)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_reportProvider(range)),
        child: ListView(
          padding: pagePaddingAman(context),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (k, l) in [('today', t(context).presetToday), ('yesterday', t(context).presetYesterday), ('week', t(context).presetWeek)])
                  QuietChip(label: l, selected: _preset == k, onTap: () => setState(() => _preset = k)),
                QuietChip(
                  icon: Icons.date_range,
                  // The chip carries the chosen span: the chips are what
                  // people look at when they wonder what they are seeing.
                  label: _rangeChipLabel(context),
                  selected: _preset == 'custom',
                  onTap: _pickRange,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                multiDay ? t(context).dateRange(longDate(range.from), longDate(range.to)) : longDate(range.from),
                style: TextStyle(color: w.muted, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            ...report.when<List<Widget>>(
              loading: () => [_summary(null, range), const SizedBox(height: 18), const SkeletonCards(rows: 3, leading: false)],
              error: (e, _) => [
                _summary(null, range),
                const SizedBox(height: 18),
                ErrorState(
                  title: t(context).reportLoadError,
                  message: e is ApiError ? e.message : '$e',
                ),
              ],
              data: (r) => _body(r, projects, multiDay, range),
            ),
          ],
        ),
      ),
    );
  }

  /// The period's two figures — metres drilled, m³ poured — with the two
  /// downloads under them. Same panel as the Activity page's summary.
  ///
  /// [totals] null while loading: the buttons are already usable (neither
  /// needs this page's figures), the figures show a dash.
  Widget _summary(Map<String, Object?>? totals, ReportRange range) {
    final w = context.colors;
    final lang = Localizations.localeOf(context).languageCode;
    String fig(Object? v) => totals == null ? '–' : reportNumber(lang, toDoubleOrNull(v) ?? 0, 1);
    final drilled = '${totals?['drilledPoints'] ?? 0}';
    final cast = '${totals?['castPoints'] ?? 0}';
    final trucks = '${totals?['trucks'] ?? 0}';

    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: QuietFigure(
                    dot: w.warnFg,
                    label: t(context).drDrilling,
                    value: fig(totals?['drilledM']),
                    unit: 'm',
                    sub: '$drilled ${t(context).activityDrilled}',
                  ),
                ),
                Container(width: 1, color: w.line),
                Expanded(
                  child: QuietFigure(
                    dot: w.brand,
                    label: t(context).drCasting,
                    value: fig(totals?['castM3']),
                    unit: 'm³',
                    sub: '$cast ${t(context).activityPoured} · $trucks TM',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // minHeight, not a fixed height: a large system font wraps
                // instead of clipping (the cut-off label, 23 Nov 2026).
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                    child: OutlinedButton.icon(
                      onPressed: _downloading ? null : () => _downloadExcel(range),
                      icon: _downloading ? const _Spin() : const Icon(Icons.table_view, size: 18),
                      label: Text(t(context).downloadExcelShort, textAlign: TextAlign.center),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // The same picture as the web's "Laporan harian", to send to
                // the group. Daniel, 22 Nov 2026.
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                    child: FilledButton.icon(
                      style: quietPrimary(context),
                      onPressed: () => context.push('/reports/daily?date=${isoDate(range.to)}'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(t(context).drTitle, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(Map<String, Object?> r, Map<String, Map<String, Object?>> projects, bool multiDay, ReportRange range) {
    final w = context.colors;
    final drilling = [for (final x in (r['drilling'] as List?) ?? const []) (x as Map).cast<String, Object?>()];
    final casting = [for (final x in (r['casting'] as List?) ?? const []) (x as Map).cast<String, Object?>()];
    final totals = ((r['totals'] as Map?) ?? const {}).cast<String, Object?>();
    final operators = [for (final x in (r['operators'] as List?) ?? const []) (x as Map).cast<String, Object?>()];

    final ids = <String>{for (final x in drilling) '${x['projectID']}', for (final x in casting) '${x['projectID']}'}.toList()
      ..sort((a, b) => '${projects[a]?['code'] ?? a}'.compareTo('${projects[b]?['code'] ?? b}'));

    return [
      _summary(totals, range),
      if (operators.isNotEmpty) ...[
        const SizedBox(height: 28),
        _OperatorCard(operators: operators),
      ],
      if (ids.isEmpty) ...[
        const SizedBox(height: 18),
        EmptyState(message: t(context).noPointsThatDay),
      ],
      for (final id in ids) ...[
        const SizedBox(height: 32),
        _ProjectCard(
          code: projects[id] == null ? t(context).projectNo(id) : '${projects[id]!['code']}',
          name: projects[id] == null ? '' : '${projects[id]!['name'] ?? ''}',
          // Only for ONE day: the daily report is one day by definition.
          onDailyReport: multiDay ? null : () => context.push('/reports/daily?project=$id&date=${isoDate(range.to)}'),
          drilling: [for (final x in drilling) if ('${x['projectID']}' == id) x],
          casting: [for (final x in casting) if ('${x['projectID']}' == id) x],
          showDate: multiDay,
        ),
      ],
      const SizedBox(height: 18),
      Text(t(context).pullToReload, textAlign: TextAlign.center, style: TextStyle(color: w.faint, fontSize: 12)),
    ];
  }
}

class _Spin extends StatelessWidget {
  const _Spin();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}

/// Thin line between rows inside a panel.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) => Container(height: 1, color: context.colors.line);
}

/// Metres drilled per rig operator in the period (finished drill logs only).
class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.operators});

  final List<Map<String, Object?>> operators;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuietHeading(code: t(context).drillOperator),
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, o) in operators.indexed) ...[
                if (i > 0) const _Hairline(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${o['name']}',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: w.ink)),
                            const SizedBox(height: 2),
                            Text(
                              [for (final c in (o['pilePointCodes'] as List?) ?? const []) '$c'].join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: w.faint, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMeters(toDoubleOrNull(o['meters']), decimals: 1),
                              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14.5, color: w.ink)),
                          const SizedBox(height: 2),
                          Text(t(context).pointsSuffix('${o['points']}'),
                              style: TextStyle(color: w.faint, fontSize: 12.5)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.code,
    required this.name,
    required this.drilling,
    required this.casting,
    required this.showDate,
    this.onDailyReport,
  });

  final String code;
  final String name;

  /// Opens this project's daily report for the day shown; null over a range.
  final VoidCallback? onDailyReport;
  final List<Map<String, Object?>> drilling;
  final List<Map<String, Object?>> casting;
  final bool showDate;

  static final _shortDate = DateFormat('d MMM', 'id');

  String _when(Map<String, Object?> x) {
    final start = DateTime.tryParse('${x['startAt']}');
    final end = DateTime.tryParse('${x['endAt']}');
    final day = DateTime.tryParse('${x['date']}');
    return [
      if (showDate && day != null) _shortDate.format(day),
      if (start != null && end != null) '${formatTime(start)}–${formatTime(end)}' else if (end != null) formatTime(end),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;

    // Section label inside the panel: "● Pengeboran · 3 titik".
    Widget section(Color dot, String text, {required bool first}) => Padding(
          padding: EdgeInsets.only(top: first ? 16 : 22, bottom: 4),
          child: QuietLabel(dot: dot, text: text),
        );

    // One pile: code bold + value plain, the details faint, the status as
    // a coloured word under them — no pills (Activity redesign).
    Widget row({
      required String code,
      required String value,
      required String sub,
      required String status,
      required Color statusColor,
      required bool first,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!first) const _Hairline(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: code,
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: w.ink),
                              ),
                              TextSpan(
                                text: '   $value',
                                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: w.ink),
                              ),
                            ],
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub, style: TextStyle(color: w.faint, fontSize: 12.5)),
                        ],
                        // UNDER the details, as on Activity: on the right, a
                        // long status ("Catatan belum ditutup") squeezed the
                        // code and value into three lines.
                        const SizedBox(height: 3),
                        Text(status,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: statusColor)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuietHeading(
          code: code,
          name: name,
          trailing: onDailyReport == null
              ? null
              : IconButton(
                  onPressed: onDailyReport,
                  tooltip: t(context).drTitle,
                  icon: Icon(Icons.image_outlined, color: w.muted, size: 20),
                ),
        ),
        QuietPanel(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (drilling.isNotEmpty) ...[
                section(w.warnFg, '${t(context).drDrilling} · ${t(context).pointsSuffix('${drilling.length}')}', first: true),
                for (final (i, x) in drilling.indexed)
                  () {
                    // Two different questions, and the word answers both.
                    // Is the hole made -> the POINT's status. Is the log
                    // closed -> the LOG's status. A log reopened to fix one
                    // reading does not undo a hole already drilled, so a pile
                    // being cast must not show as "Sedang dibor" again.
                    final (status, color) = x['status'] == 'selesai'
                        ? (t(context).statusDone, w.okFg)
                        : (x['pointStatus'] == 'sudah_bor' || x['pointStatus'] == 'sudah_cor')
                            ? (t(context).drillLogNotClosed, w.infoFg)
                            : (t(context).stageDrilling, w.warnFg);
                    return row(
                      first: i == 0,
                      code: '${x['pilePointCode']}',
                      value: 'D${x['diameterMm']} · ${formatDepthFrom(toDoubleOrNull(x['depthStartM']), toDoubleOrNull(x['depthM']))}',
                      sub: [
                        _when(x),
                        if (x['source'] == 'tanda') t(context).noLog,
                        if (x['operatorName'] != null) t(context).operatorShort('${x['operatorName']}'),
                        if (x['byName'] != null) '${x['byName']}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      status: status,
                      statusColor: color,
                    );
                  }(),
              ],
              if (casting.isNotEmpty) ...[
                section(w.brand, '${t(context).drCasting} · ${t(context).pointsSuffix('${casting.length}')}',
                    first: drilling.isEmpty),
                for (final (i, x) in casting.indexed)
                  () {
                    final over = toDoubleOrNull(x['overusePercent']);
                    final (status, color) = switch (x['status']) {
                      'diperiksa' => (t(context).statusChecked, w.okFg),
                      'selesai' => (t(context).statusDone, w.infoFg),
                      _ => (t(context).stageCasting, w.brand),
                    };
                    return row(
                      first: i == 0,
                      code: '${x['pilePointCode']}',
                      value: t(context).statCastSub(
                          (toDoubleOrNull(x['volumeM3']) ?? 0).toStringAsFixed(1).replaceAll('.', ','), '${x['trucks']}'),
                      sub: [
                        _when(x),
                        t(context).theoreticalOf(
                          (toDoubleOrNull(x['theoreticalM3']) ?? 0).toStringAsFixed(1).replaceAll('.', ','),
                          over == null ? '' : t(context).percentParens(over >= 0 ? '+' : '', over.toStringAsFixed(0)),
                        ),
                        if (x['byName'] != null) '${x['byName']}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      status: status,
                      statusColor: color,
                    );
                  }(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Apa yang diminta dari layar pilihan: rentangnya, dan lembar mana saja.
typedef _ExcelChoice = ({bool whole, List<String> sheets});

/// Pilihan sebelum mengunduh: rentang, lalu lembar mana yang dibuat.
///
/// Satu berkas memuat TIGA laporan untuk tiga pembaca — rekap tiang untuk
/// pengawas, mutu beton untuk QC, rekap operator untuk kantor. Yang
/// mengirimkannya ke klien hampir tidak pernah mau ketiganya sekaligus,
/// jadi ketiganya dapat dimatikan satu-satu. Minimal satu harus menyala:
/// berkas tanpa lembar bukan berkas.
class _ExcelOptionsSheet extends StatefulWidget {
  const _ExcelOptionsSheet({required this.range});

  final ReportRange range;

  @override
  State<_ExcelOptionsSheet> createState() => _ExcelOptionsSheetState();
}

class _ExcelOptionsSheetState extends State<_ExcelOptionsSheet> {
  bool _whole = false;
  // Daftar lembar yang SAMA dengan layar web (`LEMBAR_REKAP`). Berbeda,
  // unduhan dari HP diam-diam kekurangan lembar yang sudah lama ada di
  // berkas yang sama — dan yang mengunduhnya dari lapangan tidak punya
  // cara mengetahuinya.
  final _sheets = {
    'tiang': true,
    'beton': true,
    'operator': true,
    'pemasok': true,
  };

  bool get _none => !_sheets.values.any((v) => v);

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final range = widget.range;
    Widget period(IconData icon, String title, String body, bool value) => RadioListTile<bool>(
          value: value,
          secondary: Icon(icon, color: w.brand),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
          subtitle: Text(body),
        );
    Widget sheet(String key, String title, String body) => SwitchListTile(
          value: _sheets[key] ?? false,
          onChanged: (v) => setState(() => _sheets[key] = v),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
          subtitle: Text(body),
        );
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(context).excelOptionsTitle,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _GroupLabel(t(context).excelPeriodLabel),
              RadioGroup<bool>(
                groupValue: _whole,
                onChanged: (v) => setState(() => _whole = v ?? false),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    period(
                      Icons.date_range,
                      t(context).thisPeriod,
                      range.from == range.to
                          ? longDate(range.from)
                          : t(context).dateRange(longDate(range.from), longDate(range.to)),
                      false,
                    ),
                    period(Icons.all_inclusive, t(context).fullRecap,
                        t(context).fullRecapBody(longDate(range.to)), true),
                  ],
                ),
              ),
              const Divider(height: 24),
              _GroupLabel(t(context).excelSheetsLabel),
              sheet('tiang', t(context).sheetPiles, t(context).sheetPilesBody),
              sheet('beton', t(context).sheetConcrete, t(context).sheetConcreteBody),
              sheet('operator', t(context).sheetOperators, t(context).sheetOperatorsBody),
              sheet('pemasok', t(context).sheetSupplier, t(context).sheetSupplierBody),
              if (_none)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t(context).pickAtLeastOneSheet,
                      style: TextStyle(color: w.badFg, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: Dimens.minTouch + 4,
                child: FilledButton.icon(
                  onPressed: _none
                      ? null
                      : () => Navigator.pop(context, (
                            whole: _whole,
                            sheets: [
                              for (final e in _sheets.entries)
                                if (e.value) e.key,
                            ],
                          )),
                  icon: const Icon(Icons.download),
                  label: Text(t(context).download),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(text.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: context.colors.faint,
            )),
      );
}
