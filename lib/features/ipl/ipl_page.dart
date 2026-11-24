import 'dart:async';
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

  /// How many GS values came back from the phone's draft on this screen —
  /// shown in a banner so the surveyor knows they were kept, not sent.
  int _restored = 0;

  /// Pending draft write; typing is saved a moment after the last key.
  Timer? _draftTimer;

  /// Draft key the controllers currently belong to. Fixed when they are
  /// filled, so a write that lands after switching project or date still
  /// goes to the draft it was typed for.
  String? _draftKeyNow;

  /// Held from `initState`: the draft is still written in `dispose`, and
  /// `ref` must not be used there.
  late final AppDatabase _db;

  @override
  void initState() {
    super.initState();
    _db = ref.read(dbProvider);
  }

  @override
  void dispose() {
    // Typing in the last half second is still saved on the way out.
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraft();
    }
    for (final c in _gs.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// DRAFT GS ON THE PHONE (Daniel, 24 Nov 2026: "apa yang dia udah ketik
  /// disimpan dulu ... jadi dia bisa cicil"). A project can have 180 points;
  /// the surveyor shoots them over hours, leaves the screen, loses signal.
  /// Everything typed is kept per user, project and date in `LocalMeta`
  /// until the IPL is saved for sending — then the document holds it and
  /// the draft is dropped.
  String? _draftKey() {
    final user = ref.read(userProvider);
    if (user == null || _projectId == null) return null;
    return 'ipl_draft:${user.id}:$_projectId:$_date';
  }

  Map<String, String> _draftValues() => {
        for (final e in _gs.entries)
          // A line that was in the document and is now emptied is kept as
          // '' so it stays emptied after reopening.
          if (e.value.text.trim().isNotEmpty || _lineUuid.containsKey(e.key)) e.key: e.value.text.trim(),
      };

  void _queueDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraft);
  }

  void _saveDraft() {
    final key = _draftKeyNow;
    if (key == null) return;
    final values = _draftValues();
    _db.writeMeta(key, values.isEmpty ? null : jsonEncode(values)).ignore();
  }

  /// Put the drafted GS back over what the document holds — the draft is
  /// newer: it is what was typed after the last send.
  Future<void> _restoreDraft(String loadKey) async {
    final key = _draftKeyNow;
    if (key == null) return;
    final raw = await _db.readMeta(key);
    if (!mounted || _loadedFor != loadKey || raw == null) return;
    final Map<String, Object?> values;
    try {
      values = (jsonDecode(raw) as Map).cast<String, Object?>();
    } on FormatException {
      return;
    }
    var n = 0;
    for (final e in values.entries) {
      final text = '${e.value ?? ''}';
      final c = _field(e.key);
      if (c.text != text) {
        c.text = text;
        if (text.isNotEmpty) n++;
      }
    }
    setState(() => _restored = n);
  }

  TextEditingController _field(String pile) => _gs.putIfAbsent(pile, TextEditingController.new);

  Map<String, Object?> _bodyOf(DocumentRow d) => (jsonDecode(d.body) as Map).cast<String, Object?>();

  bool _sameDay(DocumentRow d) {
    final b = _bodyOf(d);
    return '${b['projectID']}' == '$_projectId' && '${b['date']}' == _date;
  }

  /// The IPL still being worked on for this project and date — never a
  /// confirmed one. A confirmed IPL is closed; more points for the same
  /// day go into a NEW IPL ("IPL susulan", Daniel 23 Nov 2026: the work
  /// ran faster than planned), which needs its own confirmation.
  DocumentRow? _existing(List<DocumentRow> docs) {
    for (final d in docs) {
      if (_sameDay(d) && d.serverStatus != 'dikonfirmasi') return d;
    }
    return null;
  }

  /// Fill the fields from the document for this project and date, once.
  void _loadFrom(DocumentRow? doc) {
    final key = '$_projectId|$_date|${doc?.uuid}';
    if (_loadedFor == key) return;
    // Switching away: what was typed for the old project/date is saved now.
    if (_draftTimer?.isActive ?? false) {
      _draftTimer!.cancel();
      _saveDraft();
    }
    _loadedFor = key;
    _restored = 0;
    _draftKeyNow = doc?.serverStatus == 'dikonfirmasi' ? null : _draftKey();
    // After the frame: it may call setState, and this runs during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreDraft(key));
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
      // The document holds it now; the draft is done.
      _draftTimer?.cancel();
      final key = _draftKeyNow;
      if (key != null) await _db.writeMeta(key, null);
      if (!mounted) return;
      setState(() => _restored = 0);
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
    // Points already cleared by a confirmed IPL of the same day are not
    // offered again; what is left goes into the follow-up IPL.
    final confirmedToday = [for (final d in docs) if (_sameDay(d) && d.serverStatus == 'dikonfirmasi') d];
    final cleared = <String>{
      for (final d in confirmedToday)
        for (final l in (_bodyOf(d)['lines'] as List?) ?? const []) '${(l as Map)['pilePointUuid']}',
    };

    final pilesAsync = _projectId == null
        ? const AsyncData(<Map<String, Object?>>[])
        : ref.watch(pilePointsProvider(_projectId!));
    final inDoc = _lineUuid.keys.toSet();
    final piles = [
      for (final p in pilesAsync.value ?? const <Map<String, Object?>>[])
        if (inDoc.contains('${p['uuid']}') ||
            (p['status'] == 'belum_bor' && p['checkedAt'] == null && !cleared.contains('${p['uuid']}')))
          p,
    ];
    final q = _search.trim().toLowerCase();
    final shown = [for (final p in piles) if (q.isEmpty || '${p['code']}'.toLowerCase().contains(q)) p];
    final filled = [for (final p in piles) if ((_gs['${p['uuid']}']?.text.trim() ?? '').isNotEmpty) p];
    final anyError = filled.any((p) => _check(context, p).error != null);
    final showSend = !locked && _projectId != null && piles.isNotEmpty;
    // Why the send button does nothing yet; `null` = it can send.
    final String? blocked = _saving
        ? null
        : filled.isEmpty
            ? l.iplNothingFilledBody
            : anyError
                ? l.iplFixErrors
                : null;
    final canSend = !_saving && blocked == null;

    return Scaffold(
      appBar: AppBar(title: Text(l.iplTitle)),
      // FLOATING, not at the end of the list (Daniel, 24 Nov 2026: 180
      // points to scroll past to reach it). Always tappable: when it cannot
      // send yet it says why instead of sitting there grey.
      floatingActionButton: showSend
          ? FloatingActionButton.extended(
              heroTag: 'ipl-send',
              backgroundColor: canSend ? w.ink : w.surface2,
              foregroundColor: canSend ? w.surface : w.muted,
              onPressed: _saving
                  ? null
                  : () {
                      if (canSend) {
                        _send(piles, doc).ignore();
                      } else {
                        showSnack(context, blocked!, icon: Icons.info_outline);
                      }
                    },
              icon: _saving
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: w.muted),
                    )
                  : const Icon(Icons.send),
              label: Text(doc == null ? l.iplSend('${filled.length}') : l.iplResend('${filled.length}')),
            )
          : null,
      body: ListView(
        // Room under the last card so the floating button never covers it.
        padding: pagePaddingAman(context).copyWith(
          bottom: pagePaddingAman(context).bottom + (showSend ? 88 : 0),
        ),
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
          if (confirmedToday.isNotEmpty && (doc == null || doc.serverStatus != 'dikonfirmasi'))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TerraBanner(
                kind: BannerKind.info,
                icon: Icons.playlist_add,
                title: l.iplFollowUpTitle,
                body: l.iplFollowUpBody('${cleared.length}'),
              ),
            ),
          if (_projectId == null)
            TerraBanner(kind: BannerKind.info, title: l.pickProject)
          else if (pilesAsync.isLoading && !pilesAsync.hasValue)
            const LoadingState()
          else if (piles.isEmpty)
            EmptyState(message: l.iplNoPiles)
          else ...[
            if (_restored > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.save_outlined,
                  title: l.iplDraftRestored('$_restored'),
                  body: l.iplDraftRestoredBody,
                ),
              ),
            if (!locked && filled.isEmpty && _restored == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TerraBanner(kind: BannerKind.info, title: l.iplNothingFilled, body: l.iplNothingFilledBody),
              ),
            if (!locked && filled.isNotEmpty && anyError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TerraBanner(kind: BannerKind.warning, title: l.iplFixErrors),
              ),
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
                  onChanged: () {
                    setState(() {});
                    _queueDraft();
                  },
                ),
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
