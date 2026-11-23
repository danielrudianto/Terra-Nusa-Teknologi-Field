import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/i18n.dart';
import '../../core/network/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/quiet.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import 'daily_report.dart';
import 'daily_report_actions.dart';

/// DAILY REPORT ON THE PHONE — the same picture as the web's "Laporan
/// harian", ready to share to the WhatsApp group.
///
/// Asked by Daniel, 22 Nov 2026: "Pengen bisa dilakukan di hp juga". Opened
/// from the Reports page, so it has the same audience (level 4+ and
/// Engineering); the server checks it again.
///
/// Needs signal: the report is every phone's data, read from the server.
class DailyReportPage extends ConsumerStatefulWidget {
  const DailyReportPage({super.key, this.projectId, this.date});

  /// Pre-selected project and day — from a project card on the Reports page.
  final int? projectId;
  final DateTime? date;

  @override
  ConsumerState<DailyReportPage> createState() => _DailyReportPageState();
}

class _Result {
  const _Result(this.report, this.png);
  final DailyReport report;
  final Uint8List? png;
}

class _DailyReportPageState extends ConsumerState<DailyReportPage> {
  int? _projectId;

  /// today | yesterday | custom
  String _preset = 'today';
  DateTime? _customDay;

  bool _loading = false;
  String? _error;
  _Result? _result;
  bool _busy = false;

  /// Past days are kept for this visit: their data no longer changes, and
  /// flipping between two days should not wait for the server each time.
  /// TODAY is never kept — it changes all day.
  final _cache = <String, _Result>{};

  /// Guards against an older, slower request painting over a newer one.
  int _seq = 0;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  DateTime get _date {
    final today = _day(DateTime.now());
    return switch (_preset) {
      'yesterday' => today.subtract(const Duration(days: 1)),
      'custom' when _customDay != null => _customDay!,
      _ => today,
    };
  }

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    final d = widget.date;
    if (d != null) {
      final today = _day(DateTime.now());
      if (_day(d) == today) {
        _preset = 'today';
      } else if (_day(d) == today.subtract(const Duration(days: 1))) {
        _preset = 'yesterday';
      } else {
        _preset = 'custom';
        _customDay = _day(d);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _lang => Localizations.localeOf(context).languageCode;

  Future<void> _load() async {
    final project = _projectId;
    if (project == null || !mounted) return;
    final date = _date;
    final key = '$project/${isoDate(date)}';
    final seq = ++_seq;

    final kept = _cache[key];
    if (kept != null) {
      setState(() {
        _result = kept;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final made = await makeDailyReport(ref, t(context), _lang, project, date);
      if (!mounted || seq != _seq) return;
      final result = _Result(made.report, made.png);
      if (_day(date) != _day(DateTime.now())) _cache[key] = result;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = e is ApiError ? e.message : '$e');
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _pickDay() async {
    final today = _day(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2025),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customDay = _day(picked);
      _preset = 'custom';
    });
    await _load();
  }

  Future<void> _share() async {
    final r = _result;
    if (r?.png == null) return;
    setState(() => _busy = true);
    await shareDailyReport(context, r!.png!, r.report.fileName);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    final r = _result;
    if (r?.png == null) return;
    setState(() => _busy = true);
    await saveDailyReport(context, r!.png!, r.report.fileName);
    if (mounted) setState(() => _busy = false);
  }

  /// Project list in a bottom sheet — big rows, code bold and the name
  /// muted, a check on the chosen one. The dropdown it replaces cut the name
  /// off and opened a cramped menu (Daniel, 23 Nov 2026: "select nya busuk").
  Future<void> _pickProject(List<Map<String, Object?>> projects) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _ProjectSheet(projects: projects, selected: _projectId),
    );
    if (picked == null || !mounted || picked == _projectId) return;
    setState(() => _projectId = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final projects = ref.watch(castingProjectsProvider).value ?? const <Map<String, Object?>>[];
    Map<String, Object?>? chosen;
    for (final p in projects) {
      if (toIntOrNull(p['id']) == _projectId) chosen = p;
    }
    final r = _result;
    final canAct = !_busy && !_loading && r?.png != null;

    return Scaffold(
      appBar: AppBar(title: Text(t(context).drTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          _cache.clear();
          await _load();
        },
        child: ListView(
          padding: pagePaddingAman(context),
          children: [
            QuietPanel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: projects.isEmpty ? null : () => _pickProject(projects),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t(context).drProject,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: w.muted)),
                                const SizedBox(height: 3),
                                if (chosen == null)
                                  Text(t(context).drPickProject,
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: w.faint))
                                else ...[
                                  Text('${chosen['code']}',
                                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: w.ink)),
                                  Text(
                                    '${chosen['name'] ?? ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, color: w.muted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.expand_more, color: w.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (k, l) in [('today', t(context).presetToday), ('yesterday', t(context).presetYesterday)])
                  QuietChip(
                    label: l,
                    selected: _preset == k,
                    onTap: () {
                      setState(() => _preset = k);
                      unawaited(_load());
                    },
                  ),
                QuietChip(
                  icon: Icons.event,
                  label: _preset == 'custom' && _customDay != null
                      ? DateFormat('d MMM yyyy', 'id').format(_customDay!)
                      : t(context).drPickDay,
                  selected: _preset == 'custom',
                  onTap: _pickDay,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(longDate(_date), style: TextStyle(color: w.muted, fontSize: 13)),
            ),
            const SizedBox(height: 14),
            if (_projectId == null)
              EmptyState(message: t(context).drPickProject, icon: Icons.apartment)
            else if (_loading)
              const SkeletonCards(rows: 2, leading: false)
            else if (_error != null)
              ErrorState(title: t(context).drLoadFailed, message: _error, onRetry: _load)
            else if (r != null && r.png == null)
              EmptyState(message: t(context).drEmpty(longDate(_date)), icon: Icons.event_busy)
            else if (r != null) ...[
              QuietPanel(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Pinch to zoom: the picture is 1200 wide, the phone is not.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.memory(r.png!, width: double.infinity, fit: BoxFit.fitWidth, gaplessPlayback: true),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Same pair as the Activity page: Simpan, and the black
                    // "Kirim ke WA".
                    Row(
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                            child: OutlinedButton.icon(
                              onPressed: canAct ? _save : null,
                              icon: const Icon(Icons.download, size: 18),
                              label: Text(t(context).drSave, textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                            child: FilledButton.icon(
                              style: quietPrimary(context),
                              onPressed: canAct ? _share : null,
                              icon: _busy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.share, size: 18),
                              label: Text(t(context).activitySendWa, textAlign: TextAlign.center),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(t(context).drZoomHint,
                  textAlign: TextAlign.center, style: TextStyle(color: w.faint, fontSize: 12)),
              const SizedBox(height: 18),
              // After the picture, not before it: it explains what is drawn,
              // and pushed the picture itself below the fold.
              TerraBanner(kind: BannerKind.info, title: t(context).drNoteTitle, body: t(context).drNote),
            ],
          ],
        ),
      ),
    );
  }
}

/// The project list: one big row per project.
class _ProjectSheet extends StatelessWidget {
  const _ProjectSheet({required this.projects, required this.selected});

  final List<Map<String, Object?>> projects;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, 8),
              child: Text(t(context).drProject,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: projects.length,
                separatorBuilder: (_, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Dimens.pagePadding),
                  child: Container(height: 1, color: w.line),
                ),
                itemBuilder: (c, i) {
                  final p = projects[i];
                  final id = toIntOrNull(p['id']);
                  final on = id == selected;
                  return InkWell(
                    onTap: id == null ? null : () => Navigator.pop(c, id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Dimens.pagePadding, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${p['code']}',
                                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: w.ink)),
                                  const SizedBox(height: 2),
                                  Text('${p['name'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12.5, color: w.muted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (on) Icon(Icons.check, color: w.ink) else const SizedBox(width: 24),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
