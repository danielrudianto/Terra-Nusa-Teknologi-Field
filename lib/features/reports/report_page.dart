import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/view_states.dart';
import '../../core/i18n.dart';

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
  DateTime _customDay = DateTime.now();

  /// An Excel download is running.
  bool _downloading = false;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  ReportRange get _range {
    final today = _day(DateTime.now());
    return switch (_preset) {
      'yesterday' => (from: today.subtract(const Duration(days: 1)), to: today.subtract(const Duration(days: 1))),
      'week' => (from: today.subtract(const Duration(days: 6)), to: today),
      'custom' => (from: _day(_customDay), to: _day(_customDay)),
      _ => (from: today, to: today),
    };
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDay,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      _customDay = picked;
      _preset = 'custom';
    });
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
                  ChoiceChip(label: Text(l), selected: _preset == k, onSelected: (_) => setState(() => _preset = k)),
                ChoiceChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(_preset == 'custom' ? DateFormat('d MMM', 'id').format(_customDay) : t(context).pickDate),
                  selected: _preset == 'custom',
                  onSelected: (_) => _pickDay(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              multiDay ? t(context).dateRange(longDate(range.from), longDate(range.to)) : longDate(range.from),
              style: TextStyle(color: w.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: Dimens.minTouch,
              child: FilledButton.tonalIcon(
                onPressed: _downloading ? null : () => _downloadExcel(range),
                icon: _downloading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_view),
                label: Text(_downloading ? t(context).preparingExcel : t(context).downloadExcel),
              ),
            ),
            const SizedBox(height: 14),
            ...report.when<List<Widget>>(
              loading: () => const [SkeletonCards(rows: 3, leading: false)],
              error: (e, _) => [
                ErrorState(
                  title: t(context).reportLoadError,
                  message: e is ApiError ? e.message : '$e',
                ),
              ],
              data: (r) => _body(r, projects, multiDay),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(Map<String, Object?> r, Map<String, Map<String, Object?>> projects, bool multiDay) {
    final w = context.colors;
    final drilling = [for (final x in (r['drilling'] as List?) ?? const []) (x as Map).cast<String, Object?>()];
    final casting = [for (final x in (r['casting'] as List?) ?? const []) (x as Map).cast<String, Object?>()];
    final totals = ((r['totals'] as Map?) ?? const {}).cast<String, Object?>();
    final operators = [for (final x in (r['operators'] as List?) ?? const []) (x as Map).cast<String, Object?>()];

    final ids = <String>{for (final x in drilling) '${x['projectID']}', for (final x in casting) '${x['projectID']}'}.toList()
      ..sort((a, b) => '${projects[a]?['code'] ?? a}'.compareTo('${projects[b]?['code'] ?? b}'));

    return [
      Row(
        children: [
          _Stat(label: t(context).statDrilledPoints, value: '${totals['drilledPoints'] ?? 0}', sub: formatMeters(toDoubleOrNull(totals['drilledM']), decimals: 1)),
          const SizedBox(width: 10),
          _Stat(
            label: t(context).statCastPoints,
            value: '${totals['castPoints'] ?? 0}',
            sub: t(context).statCastSub(
                (toDoubleOrNull(totals['castM3']) ?? 0).toStringAsFixed(1).replaceAll('.', ','), '${totals['trucks'] ?? 0}'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (operators.isNotEmpty) _OperatorCard(operators: operators),
      if (ids.isEmpty) EmptyState(message: t(context).noPointsThatDay),
      for (final id in ids)
        _ProjectCard(
          title: projects[id] == null ? t(context).projectNo(id) : '${projects[id]!['code']} · ${projects[id]!['name']}',
          drilling: [for (final x in drilling) if ('${x['projectID']}' == id) x],
          casting: [for (final x in casting) if ('${x['projectID']}' == id) x],
          showDate: multiDay,
        ),
      const SizedBox(height: 8),
      Text(t(context).pullToReload,
          style: TextStyle(color: w.faint, fontSize: 12)),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.sub});

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: w.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: w.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: w.faint)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: w.ink, height: 1.1)),
            Text(sub, style: TextStyle(color: w.muted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

/// Metres drilled per rig operator in the period (finished drill logs only).
class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.operators});

  final List<Map<String, Object?>> operators;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.engineering, size: 18, color: w.brand),
              const SizedBox(width: 6),
              Text(t(context).drillOperator, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
            ],
          ),
          const SizedBox(height: 6),
          for (final o in operators)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${o['name']}', style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
                        Text(
                          [for (final c in (o['pilePointCodes'] as List?) ?? const []) '$c'].join(', '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: w.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatMeters(toDoubleOrNull(o['meters']), decimals: 1),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                      Text(t(context).pointsSuffix('${o['points']}'), style: TextStyle(color: w.muted, fontSize: 12.5)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.title, required this.drilling, required this.casting, required this.showDate});

  final String title;
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
    Widget heading(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: w.brand),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
            ],
          ),
        );

    Widget row({required String code, required String main, required String sub, required StatusBadge badge}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$code · $main', style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
                    if (sub.isNotEmpty) Text(sub, style: TextStyle(color: w.muted, fontSize: 13)),
                  ],
                ),
              ),
              badge,
            ],
          ),
        );

    return ListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
          if (drilling.isNotEmpty) ...[
            heading(Icons.construction, t(context).drilledCount(drilling.length)),
            for (final x in drilling)
              row(
                code: '${x['pilePointCode']}',
                main: 'D${x['diameterMm']} · ${formatMeters(toDoubleOrNull(x['depthM']))}',
                sub: [
                  _when(x),
                  if (x['source'] == 'tanda') t(context).noLog,
                  if (x['operatorName'] != null) t(context).operatorShort('${x['operatorName']}'),
                  if (x['byName'] != null) '${x['byName']}',
                ].where((s) => s.isNotEmpty).join(' · '),
                // Dua pertanyaan yang berbeda, dan lencananya menjawab
                // keduanya. Lubangnya sudah jadi belum -> status TITIK.
                // Lognya sudah ditutup belum -> status LOG. Log yang dibuka
                // lagi untuk membetulkan satu bacaan tidak membatalkan lubang
                // yang sudah dibor, jadi titik yang sedang dicor tidak boleh
                // lagi muncul sebagai "Sedang dibor".
                badge: x['status'] == 'selesai'
                    ? StatusBadge(text: t(context).statusDone, bg: w.okBg, fg: w.okFg)
                    : (x['pointStatus'] == 'sudah_bor' || x['pointStatus'] == 'sudah_cor')
                        ? StatusBadge(
                            text: t(context).drillLogNotClosed,
                            bg: w.infoBg,
                            fg: w.infoFg,
                            icon: Icons.lock_open,
                          )
                        : StatusBadge(text: t(context).stageDrilling, bg: w.warnBg, fg: w.warnFg),
              ),
          ],
          if (casting.isNotEmpty) ...[
            heading(Icons.foundation, t(context).castCount(casting.length)),
            for (final x in casting)
              () {
                final over = toDoubleOrNull(x['overusePercent']);
                return row(
                  code: '${x['pilePointCode']}',
                  main: t(context).statCastSub((toDoubleOrNull(x['volumeM3']) ?? 0).toStringAsFixed(1).replaceAll('.', ','), '${x['trucks']}'),
                  sub: [
                    _when(x),
                    t(context).theoreticalOf(
                      (toDoubleOrNull(x['theoreticalM3']) ?? 0).toStringAsFixed(1).replaceAll('.', ','),
                      over == null ? '' : t(context).percentParens(over >= 0 ? '+' : '', over.toStringAsFixed(0)),
                    ),
                    if (x['byName'] != null) '${x['byName']}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  badge: switch (x['status']) {
                    'diperiksa' => StatusBadge(text: t(context).statusChecked, bg: w.okBg, fg: w.okFg),
                    'selesai' => StatusBadge(text: t(context).statusDone, bg: w.infoBg, fg: w.infoFg),
                    _ => StatusBadge(text: t(context).stageCasting, bg: w.checkedBg, fg: w.checkedFg),
                  },
                );
              }(),
          ],
        ],
      ),
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
  final _sheets = {'tiang': true, 'beton': true, 'operator': true};

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
