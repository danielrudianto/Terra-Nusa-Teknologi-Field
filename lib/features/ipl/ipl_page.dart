import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/util/reasons.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/quiet.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../casting/level_reference.dart';

/// IPL — Izin Pelaksanaan Lapangan (23 Nov 2026).
///
/// The surveyor's ONE job: pick the points that can be drilled tomorrow and
/// shoot the actual ground level (GS) of each. The office confirms it on the
/// web; only then may the rig crew start a drill log on those points, and
/// the GS they see is this one — they no longer type it.
///
/// One document per project per date. Sent again after a rejection, with
/// the office's reason shown on top.
class IplPage extends ConsumerStatefulWidget {
  const IplPage({super.key});

  @override
  ConsumerState<IplPage> createState() => _IplPageState();
}

class _IplPageState extends ConsumerState<IplPage> {
  int? _projectId;
  late String _date = isoDate(DateTime.now().add(const Duration(days: 1)));
  String _search = '';
  bool _saving = false;

  /// pile uuid → GS field. Rebuilt whenever project or date changes.
  final Map<String, TextEditingController> _gs = {};

  /// pile uuid → line uuid, kept from the existing document so a resend
  /// updates the same lines instead of making new ones.
  final Map<String, String> _lineUuid = {};

  /// "project|date" the fields were last filled for.
  String? _loadedFor;
  bool _defaultApplied = false;

  @override
  void dispose() {
    for (final c in _gs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(String pile) => _gs.putIfAbsent(pile, TextEditingController.new);

  Map<String, Object?> _bodyOf(DocumentRow d) => (jsonDecode(d.body) as Map).cast<String, Object?>();

  DocumentRow? _existing(List<DocumentRow> docs) {
    for (final d in docs) {
      final b = _bodyOf(d);
      if ('${b['projectID']}' == '$_projectId' && '${b['date']}' == _date) return d;
    }
    return null;
  }

  /// Fill the fields from the document for this project and date, once.
  void _loadFrom(DocumentRow? doc) {
    final key = '$_projectId|$_date';
    if (_loadedFor == key) return;
    _loadedFor = key;
    // Fresh controllers, not cleared ones: this runs during build, and
    // changing an attached controller here would rebuild mid-build. The old
    // ones are let go after the frame.
    final old = _gs.values.toList();
    _gs.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
    _lineUuid.clear();
    if (doc == null) return;
    for (final l in (_bodyOf(doc)['lines'] as List?) ?? const []) {
      final m = (l as Map).cast<String, Object?>();
      final pile = '${m['pilePointUuid']}';
      _lineUuid[pile] = '${m['uuid']}';
      final gs = toDoubleOrNull(m['groundLevel']);
      _field(pile).text = gs == null ? '' : decimalText(gs, decimals: 3).replaceAll('.', ',');
    }
  }

  /// The GS typed for a pile, or the reason it cannot be sent.
  ({double? gs, String? error}) _check(BuildContext context, Map<String, Object?> pile) {
    final text = _gs['${pile['uuid']}']?.text.trim() ?? '';
    if (text.isEmpty) return (gs: null, error: null);
    final gs = parseNumber(text);
    if (gs == null) return (gs: null, error: t(context).iplGsInvalid);
    final tip = toDoubleOrNull(pile['tipLevel']);
    if (tip != null && gs <= tip) return (gs: null, error: t(context).iplGsBelowTip(formatElevation(tip)));
    return (gs: gs, error: null);
  }

  Future<void> _send(List<Map<String, Object?>> piles, DocumentRow? doc) async {
    final l = t(context);
    final user = ref.read(userProvider);
    if (user == null || _projectId == null) return;
    final lines = <Map<String, Object?>>[];
    for (final p in piles) {
      final r = _check(context, p);
      if (r.error != null) {
        showSnack(context, '${p['code']}: ${r.error}', icon: Icons.error_outline);
        return;
      }
      if (r.gs == null) continue;
      final pile = '${p['uuid']}';
      lines.add({
        'uuid': _lineUuid.putIfAbsent(pile, newUuid),
        'pilePointUuid': pile,
        'groundLevel': decimalText(r.gs!, decimals: 3),
      });
    }
    if (lines.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(dbProvider).saveDocument(
            uuid: doc?.uuid ?? newUuid(),
            entity: 'ipl',
            userId: user.id,
            body: {'projectID': _projectId, 'date': _date, 'note': null, 'lines': lines},
          );
      if (!mounted) return;
      showSnack(context, l.iplSaved('${lines.length}'));
      ref.read(syncProvider.notifier).run(diminta: true).ignore();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final projects = ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[];
    final mine = ref.watch(myProjectProvider);
    if (!_defaultApplied && mine.hasValue) {
      _defaultApplied = true;
      _projectId = mine.value ?? (projects.isEmpty ? null : toIntOrNull(projects.first['id']));
    }
    final docsAsync = ref.watch(documentsProvider('ipl'));
    final docs = docsAsync.value ?? const <DocumentRow>[];
    final doc = _existing(docs);
    if (docsAsync.hasValue) _loadFrom(doc);

    final today = isoDate(DateTime.now());
    final tomorrow = isoDate(DateTime.now().add(const Duration(days: 1)));
    final locked = doc?.serverStatus == 'dikonfirmasi';

    final pilesAsync = _projectId == null
        ? const AsyncData(<Map<String, Object?>>[])
        : ref.watch(pilePointsProvider(_projectId!));
    final inDoc = _lineUuid.keys.toSet();
    final piles = [
      for (final p in pilesAsync.value ?? const <Map<String, Object?>>[])
        if (inDoc.contains('${p['uuid']}') || (p['status'] == 'belum_bor' && p['checkedAt'] == null)) p,
    ];
    final q = _search.trim().toLowerCase();
    final shown = [for (final p in piles) if (q.isEmpty || '${p['code']}'.toLowerCase().contains(q)) p];
    final filled = [for (final p in piles) if ((_gs['${p['uuid']}']?.text.trim() ?? '').isNotEmpty) p];
    final anyError = filled.any((p) => _check(context, p).error != null);

    return Scaffold(
      appBar: AppBar(title: Text(l.iplTitle)),
      body: ListView(
        padding: pagePaddingAman(context),
        children: [
          Text(l.iplIntro, style: TextStyle(color: w.muted, height: 1.4)),
          const SizedBox(height: 16),
          Text(l.projectLabel, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
          const SizedBox(height: 6),
          DropdownButtonFormField<int>(
            key: ValueKey(_projectId),
            initialValue: _projectId,
            isExpanded: true,
            hint: Text(l.pickProject),
            items: [
              for (final p in projects)
                DropdownMenuItem(
                  value: toIntOrNull(p['id']),
                  child: Text('${p['code']} · ${p['name']}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _projectId = v),
          ),
          const SizedBox(height: 16),
          Text(l.iplDateLabel, style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              QuietChip(label: l.iplTomorrow, selected: _date == tomorrow, onTap: () => setState(() => _date = tomorrow)),
              QuietChip(label: l.iplToday, selected: _date == today, onTap: () => setState(() => _date = today)),
            ],
          ),
          const SizedBox(height: 6),
          Text(longDate(DateTime.parse(_date)), style: TextStyle(color: w.muted)),
          const SizedBox(height: 16),
          if (doc != null) _StatusBanner(doc: doc),
          if (_projectId == null)
            TerraBanner(kind: BannerKind.info, title: l.pickProject)
          else if (pilesAsync.isLoading && !pilesAsync.hasValue)
            const LoadingState()
          else if (piles.isEmpty)
            EmptyState(message: l.iplNoPiles)
          else ...[
            TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.iplSearch),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            for (final p in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PileGsCard(
                  pile: p,
                  controller: _field('${p['uuid']}'),
                  error: _check(context, p).error,
                  locked: locked,
                  onChanged: () => setState(() {}),
                ),
              ),
            const SizedBox(height: 8),
            if (!locked && filled.isEmpty)
              TerraBanner(kind: BannerKind.info, title: l.iplNothingFilled, body: l.iplNothingFilledBody)
            else if (!locked && anyError)
              TerraBanner(kind: BannerKind.warning, title: l.iplFixErrors),
            FilledButton.icon(
              style: quietPrimary(context),
              onPressed: locked || _saving || filled.isEmpty || anyError ? null : () => _send(piles, doc),
              icon: const Icon(Icons.send),
              label: Text(doc == null ? l.iplSend('${filled.length}') : l.iplResend('${filled.length}')),
            ),
          ],
          const SizedBox(height: 28),
          _History(docs: docs, projects: projects),
        ],
      ),
    );
  }
}

/// Where this IPL stands: waiting to be sent, waiting for the office,
/// rejected (with the reason), or confirmed.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.doc});

  final DocumentRow doc;

  @override
  Widget build(BuildContext context) {
    final l = t(context);
    final Widget b;
    if (doc.sendStatus == 'rejected') {
      b = TerraBanner(kind: BannerKind.danger, title: l.iplRefused, body: reasonText(context, doc.reason, doc.detail));
    } else if (doc.version > doc.syncedVersion) {
      b = TerraBanner(kind: BannerKind.info, icon: Icons.cloud_upload_outlined, title: l.iplWaitingSend, body: l.iplWaitingSendBody);
    } else if (doc.serverStatus == 'dikonfirmasi') {
      b = TerraBanner(kind: BannerKind.ok, icon: Icons.verified_outlined, title: l.iplConfirmed, body: l.iplConfirmedBody);
    } else if (doc.serverStatus == 'ditolak') {
      b = TerraBanner(
        kind: BannerKind.danger,
        title: l.iplRejected,
        body: l.iplRejectedBody(doc.serverNote ?? '-'),
      );
    } else {
      b = TerraBanner(kind: BannerKind.info, icon: Icons.hourglass_top, title: l.iplWaitingOffice, body: l.iplWaitingOfficeBody);
    }
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: b);
  }
}

class _PileGsCard extends StatelessWidget {
  const _PileGsCard({
    required this.pile,
    required this.controller,
    required this.error,
    required this.locked,
    required this.onChanged,
  });

  final Map<String, Object?> pile;
  final TextEditingController controller;
  final String? error;
  final bool locked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final tip = toDoubleOrNull(pile['tipLevel']);
    final col = toDoubleOrNull(pile['cutOffLevel']);
    final dia = toIntOrNull(pile['diameterMm']);
    return QuietPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${pile['code']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: w.ink)),
          const SizedBox(height: 2),
          Text(
            [
              if (dia != null && dia > 0) 'Ø$dia',
              if (col != null) 'COL ${formatElevation(col)}',
              if (tip != null) 'Tip ${formatElevation(tip)}',
            ].join('   '),
            style: TextStyle(fontSize: 12.5, color: w.muted),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
            decoration: InputDecoration(labelText: l.iplGsLabel, suffixText: 'm', errorText: error),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

/// The surveyor's earlier IPLs, newest first, so a rejection or a
/// confirmation is seen without hunting for it.
class _History extends StatelessWidget {
  const _History({required this.docs, required this.projects});

  final List<DocumentRow> docs;
  final List<Map<String, Object?>> projects;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    if (docs.isEmpty) return const SizedBox.shrink();
    final codes = {for (final p in projects) '${p['id']}': '${p['code']}'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuietHeading(code: l.iplHistory),
        for (final d in docs.take(14))
          Builder(builder: (context) {
            final b = (jsonDecode(d.body) as Map).cast<String, Object?>();
            final n = ((b['lines'] as List?) ?? const []).length;
            final (word, color) = switch (d) {
              _ when d.sendStatus == 'rejected' => (l.iplRefused, w.badFg),
              _ when d.version > d.syncedVersion => (l.iplWaitingSend, w.muted),
              _ when d.serverStatus == 'dikonfirmasi' => (l.iplConfirmed, w.okFg),
              _ when d.serverStatus == 'ditolak' => (l.iplRejected, w.badFg),
              _ => (l.iplWaitingOffice, w.warnFg),
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(longDate(DateTime.parse('${b['date']}')),
                            style: TextStyle(fontWeight: FontWeight.w700, color: w.ink)),
                        Text('${codes['${b['projectID']}'] ?? ''} · ${l.iplPileCount('$n')}',
                            style: TextStyle(fontSize: 12.5, color: w.muted)),
                      ],
                    ),
                  ),
                  Text(word, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            );
          }),
      ],
    );
  }
}
