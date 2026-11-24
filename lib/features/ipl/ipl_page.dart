import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/format.dart';
import '../../core/util/reasons.dart';
import '../../core/widgets/app_snack.dart';
import '../../core/widgets/confirm.dart';
import '../../core/widgets/quiet.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/view_states.dart';
import '../casting/level_reference.dart';
import 'gs_dialog.dart';
import 'gs_ukur.dart';

/// IPL — Izin Pelaksanaan Lapangan (23 Nov 2026).
///
/// The office confirms on the web which points may be worked on a given
/// day; only then may the rig crew start a drill log there, and the GS they
/// see is the one confirmed here.
///
/// TWO SEPARATE THINGS on this screen (Daniel, 24 Nov 2026):
///
///  * MEASURING a GS — "bisa tuh orangnya kasih GS, tapi udah gitu belum
///    tentu dikerjain besok". Tapping a row opens a dialog with the point's
///    DESIGN GS beside the field ("kasih tau juga GS design ya berapa. Jadi
///    minim salah"); what is entered is saved on the phone at once as a
///    `gs_ukur` document (see `gs_ukur.dart`) and sent with the next sync,
///    whether or not the point is scheduled.
///  * SCHEDULING it — "tambahin checklist biar bener bener yakin yang besok
///    dikerjain ini". Ticking a point opens the same dialog, so no point is
///    ticked without its GS checked against the design. Only TICKED points
///    go into the IPL, and sending asks once more with their codes in view.
///    Ticks are kept on the phone until the IPL is sent.
///
/// The send button FLOATS (Daniel: it sat under 180 points). It is always
/// tappable; when it cannot send yet it says why.
///
/// One IPL per project per date. Sent again after a rejection, with the
/// office's reason shown on top.
class IplPage extends ConsumerStatefulWidget {
  const IplPage({super.key});

  @override
  ConsumerState<IplPage> createState() => _IplPageState();
}

enum _Filter { all, picked, unmeasured }

class _IplPageState extends ConsumerState<IplPage> {
  int? _projectId;
  late String _date = isoDate(DateTime.now().add(const Duration(days: 1)));
  String _search = '';
  _Filter _filter = _Filter.all;

  /// Points that were unmeasured when "Belum diukur" was chosen. Frozen, so
  /// a row does not vanish under the surveyor's thumb on the first key.
  Set<String> _unmeasuredShown = const {};
  bool _saving = false;

  /// pile uuid → measured GS. Refilled whenever project, date or document
  /// changes; updated from the GS dialog.
  final Map<String, double> _gs = {};

  /// Ticked pile uuids — the points that WILL be worked on that day.
  final Set<String> _picked = {};

  /// pile uuid → line uuid, kept from the existing IPL so a resend updates
  /// the same lines instead of making new ones.
  final Map<String, String> _lineUuid = {};

  /// "project|date|document" the fields were last filled for.
  String? _loadedFor;
  bool _defaultApplied = false;

  /// How many ticks came back from the phone — shown so the surveyor knows
  /// they were kept, not sent.
  int _restored = 0;

  /// Key the ticks of this project and date are kept under. `null` =
  /// nothing to keep (a confirmed IPL cannot change).
  String? _pickKey;
  Timer? _pickTimer;

  /// This user's measurements as of the last build.
  Map<String, DocumentRow> _measured = const {};

  /// Document uuid given to a point measured for the FIRST time on this
  /// screen. A second save can come before the first one is back from the
  /// database; without this it would start a second document.
  final Map<String, String> _newGsDoc = {};

  /// Held from `initState`: pending saves still run in `dispose`, and `ref`
  /// must not be used there.
  late final AppDatabase _db;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _db = ref.read(dbProvider);
    _userId = ref.read(userProvider)?.id;
  }

  @override
  void dispose() {
    _flushPicks();
    super.dispose();
  }

  // ------------------------------------------------------------- ticks

  String? _pickKeyFor(DocumentRow? doc) {
    if (_userId == null || _projectId == null || doc?.serverStatus == 'dikonfirmasi') return null;
    return 'ipl_pilih:$_userId:$_projectId:$_date';
  }

  void _queuePicks() {
    _pickTimer?.cancel();
    _pickTimer = Timer(const Duration(milliseconds: 300), _savePicks);
  }

  void _savePicks() {
    final key = _pickKey;
    if (key == null) return;
    _db.writeMeta(key, jsonEncode(_picked.toList())).ignore();
  }

  /// Ticks kept on the phone win over the IPL's lines: they are what was
  /// ticked after the last send.
  Future<void> _restorePicks(String loadKey) async {
    final key = _pickKey;
    if (key == null) return;
    final raw = await _db.readMeta(key);
    if (!mounted || _loadedFor != loadKey || raw == null) return;
    final Set<String> kept;
    try {
      kept = {for (final x in jsonDecode(raw) as List) '$x'};
    } on FormatException {
      return;
    } on TypeError {
      return;
    }
    setState(() {
      _restored = kept.difference(_picked).length;
      _picked
        ..clear()
        ..addAll(kept);
    });
  }

  void _toggle(String pile, bool on) {
    setState(() => on ? _picked.add(pile) : _picked.remove(pile));
    _queuePicks();
  }

  // ---------------------------------------------------------------- GS

  /// Write pending ticks now — leaving the screen, switching day, sending.
  void _flushPicks() {
    if (_pickTimer?.isActive ?? false) {
      _pickTimer!.cancel();
      _savePicks();
    }
  }

  /// Save a measured GS as this user's `gs_ukur` document for the point.
  Future<void> _saveGs(Map<String, Object?> pile, double gs) async {
    final uuid = '${pile['uuid']}';
    final userId = _userId;
    final projectId = toIntOrNull(pile['projectID']) ?? _projectId;
    if (userId == null || projectId == null) return;
    final existing = _measured[uuid];
    if (existing != null && gsUkurValue(existing) == gs) return;
    await saveGsUkur(
      _db,
      uuid: existing?.uuid ?? _newGsDoc.putIfAbsent(uuid, newUuid),
      userId: userId,
      projectId: projectId,
      pileUuid: uuid,
      gs: gs,
    );
  }

  /// Open the GS dialog for a point. With [tick], a confirmed GS also ticks
  /// it; without, it is only measured.
  Future<void> _askGs(Map<String, Object?> pile, {required bool tick}) async {
    final l = t(context);
    final uuid = '${pile['uuid']}';
    final gs = await showGsDialog(
      context,
      pile: pile,
      initial: _gs[uuid],
      confirmLabel: tick ? l.iplTickAndSave : l.iplSaveGs,
    );
    if (gs == null || !mounted) return;
    setState(() {
      _gs[uuid] = gs;
      if (tick) _picked.add(uuid);
    });
    if (tick) _queuePicks();
    await _saveGs(pile, gs);
  }

  // ---------------------------------------------------------- document

  Map<String, Object?> _bodyOf(DocumentRow d) => (jsonDecode(d.body) as Map).cast<String, Object?>();

  bool _sameDay(DocumentRow d) {
    final b = _bodyOf(d);
    return '${b['projectID']}' == '$_projectId' && '${b['date']}' == _date;
  }

  /// The IPL still being worked on for this project and date — never a
  /// confirmed one. A confirmed IPL is closed; more points for the same
  /// day go into a NEW IPL ("IPL susulan", Daniel 23 Nov 2026), which needs
  /// its own confirmation.
  DocumentRow? _existing(List<DocumentRow> docs) {
    for (final d in docs) {
      if (_sameDay(d) && d.serverStatus != 'dikonfirmasi') return d;
    }
    return null;
  }

  /// Fill ticks and fields for this project and date, once: GS from the
  /// surveyor's own measurements, else from the IPL; ticks from the IPL,
  /// then the ticks kept on the phone over them.
  void _loadFrom(DocumentRow? doc, Map<String, DocumentRow> measured) {
    final key = '$_projectId|$_date|${doc?.uuid}';
    if (_loadedFor == key) return;
    _flushPicks();
    _loadedFor = key;
    _restored = 0;
    _pickKey = _pickKeyFor(doc);
    _gs.clear();
    _lineUuid.clear();
    _picked.clear();
    if (doc != null) {
      for (final l in (_bodyOf(doc)['lines'] as List?) ?? const []) {
        final m = (l as Map).cast<String, Object?>();
        final pile = '${m['pilePointUuid']}';
        _lineUuid[pile] = '${m['uuid']}';
        _picked.add(pile);
        final gs = toDoubleOrNull(m['groundLevel']);
        if (gs != null) _gs[pile] = gs;
      }
    }
    for (final e in measured.entries) {
      final gs = gsUkurValue(e.value);
      if (gs != null) _gs[e.key] = gs;
    }
    // After the frame: it calls setState, and this runs during build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePicks(key));
  }

  /// The GS of a pile, or the reason it cannot be sent. The dialog already
  /// refuses a GS below the tip; checked again because a GS can also come
  /// from an older IPL.
  ({double? gs, String? error}) _check(BuildContext context, Map<String, Object?> pile) {
    final gs = _gs['${pile['uuid']}'];
    if (gs == null) return (gs: null, error: null);
    final tip = toDoubleOrNull(pile['tipLevel']);
    if (tip != null && gs <= tip) return (gs: null, error: t(context).iplGsBelowTip(formatElevation(tip)));
    return (gs: gs, error: null);
  }

  /// Ask once more with the codes in view, then save the IPL for sending.
  Future<void> _send(List<Map<String, Object?>> picked, DocumentRow? doc) async {
    final l = t(context);
    final userId = _userId;
    if (userId == null || _projectId == null || picked.isEmpty) return;
    final lines = <Map<String, Object?>>[];
    for (final p in picked) {
      final r = _check(context, p);
      if (r.gs == null) {
        showSnack(context, '${p['code']}: ${r.error ?? l.iplGsEmpty}', icon: Icons.error_outline);
        return;
      }
      final pile = '${p['uuid']}';
      lines.add({
        'uuid': _lineUuid.putIfAbsent(pile, newUuid),
        'pilePointUuid': pile,
        'groundLevel': decimalText(r.gs!, decimals: 3),
      });
    }
    const shownCodes = 24;
    final codes = [for (final p in picked) '${p['code']}'];
    final codeText = codes.length <= shownCodes
        ? codes.join(', ')
        : '${codes.take(shownCodes).join(', ')} ${l.iplConfirmMore('${codes.length - shownCodes}')}';
    final ok = await askConfirm(
      context,
      icon: Icons.fact_check_outlined,
      title: l.iplConfirmTitle,
      body: l.iplConfirmBody(longDate(DateTime.parse(_date)), '${codes.length}', codeText),
      confirmLabel: l.send,
    );
    if (!ok || !mounted) return;

    _flushPicks();
    setState(() => _saving = true);
    // Ticks kept on the phone are dropped BEFORE the IPL is written: its
    // arrival reloads this screen, and ticks still kept would be laid over
    // it and reported as "restored".
    final key = _pickKey;
    try {
      if (key != null) await _db.writeMeta(key, null);
      await _db.saveDocument(
        uuid: doc?.uuid ?? newUuid(),
        entity: 'ipl',
        userId: userId,
        body: {'projectID': _projectId, 'date': _date, 'note': null, 'lines': lines},
      );
      if (!mounted) return;
      setState(() => _restored = 0);
      showSnack(context, l.iplSaved('${lines.length}'));
      ref.read(syncProvider.notifier).run(diminta: true).ignore();
    } catch (_) {
      // Not saved: keep the ticks.
      _savePicks();
      rethrow;
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
    final measuredAsync = ref.watch(documentsProvider('gs_ukur'));
    final measured = ref.watch(gsUkurByPileProvider);
    _measured = measured;
    _userId = ref.watch(userProvider)?.id ?? _userId;
    final docs = docsAsync.value ?? const <DocumentRow>[];
    final doc = _existing(docs);
    if (docsAsync.hasValue && measuredAsync.hasValue) _loadFrom(doc, measured);

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
    bool hasGs(Map<String, Object?> p) => _gs.containsKey('${p['uuid']}');
    // Ticks for points no longer on offer (drilled since, cleared by a
    // confirmed IPL) are ignored, not sent.
    final picked = [for (final p in piles) if (_picked.contains('${p['uuid']}')) p];
    final noGs = [for (final p in picked) if (!hasGs(p)) p];
    final anyError = piles.any((p) => _check(context, p).error != null);
    final pickedError = picked.any((p) => _check(context, p).error != null);
    final unmeasured = [for (final p in piles) if (!hasGs(p)) p];

    final q = _search.trim().toLowerCase();
    final base = switch (_filter) {
      _Filter.all => piles,
      _Filter.picked => picked,
      _Filter.unmeasured => [for (final p in piles) if (_unmeasuredShown.contains('${p['uuid']}')) p],
    };
    final shown = [for (final p in base) if (q.isEmpty || '${p['code']}'.toLowerCase().contains(q)) p];

    final showSend = !locked && _projectId != null && piles.isNotEmpty;
    // Why the send button cannot send yet; `null` = it can.
    final String? blocked = picked.isEmpty
        ? l.iplNothingFilledBody
        : noGs.isNotEmpty
            ? l.iplPickedNoGs('${noGs.length}', noGs.take(5).map((p) => '${p['code']}').join(', '))
            : pickedError
                ? l.iplFixErrors
                : null;
    final canSend = !_saving && blocked == null;

    final header = <Widget>[
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
        if (!locked && picked.isEmpty && _restored == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TerraBanner(
              kind: BannerKind.info,
              icon: Icons.checklist,
              title: l.iplNothingFilled,
              body: l.iplNothingFilledBody,
            ),
          ),
        if (!locked && anyError)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TerraBanner(kind: BannerKind.warning, title: l.iplFixErrors),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            QuietChip(
              label: l.iplFilterAll('${piles.length}'),
              selected: _filter == _Filter.all,
              onTap: () => setState(() => _filter = _Filter.all),
            ),
            QuietChip(
              icon: Icons.check,
              label: l.iplFilterPicked('${picked.length}'),
              selected: _filter == _Filter.picked,
              onTap: () => setState(() => _filter = _Filter.picked),
            ),
            QuietChip(
              label: l.iplFilterUnmeasured('${unmeasured.length}'),
              selected: _filter == _Filter.unmeasured,
              onTap: () => setState(() {
                _filter = _Filter.unmeasured;
                _unmeasuredShown = {for (final p in unmeasured) '${p['uuid']}'};
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l.iplSearch),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty) EmptyState(message: l.iplFilterEmpty),
      ],
    ];
    final listed = _projectId != null && piles.isNotEmpty ? shown : const <Map<String, Object?>>[];
    final pad = pagePaddingAman(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.iplTitle)),
      floatingActionButton: showSend
          ? FloatingActionButton.extended(
              heroTag: 'ipl-send',
              backgroundColor: canSend ? w.ink : w.surface2,
              foregroundColor: canSend ? w.surface : w.muted,
              onPressed: _saving
                  ? null
                  : () {
                      if (canSend) {
                        _send(picked, doc).ignore();
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
              label: Text(doc == null ? l.iplSend('${picked.length}') : l.iplResend('${picked.length}')),
            )
          : null,
      // Built lazily: a project can have 180 open points.
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0),
            sliver: SliverList.list(children: header),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: pad.left),
            sliver: SliverList.builder(
              itemCount: listed.length,
              itemBuilder: (context, i) {
                final p = listed[i];
                final uuid = '${p['uuid']}';
                final m = measured[uuid];
                return Padding(
                  // Key per point: rows keep their identity when the list
                  // is filtered or searched.
                  key: ValueKey('ipl-$uuid'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PileRow(
                    pile: p,
                    picked: _picked.contains(uuid),
                    gs: _gs[uuid],
                    error: _check(context, p).error,
                    measuredAt: m?.updatedAt,
                    locked: locked,
                    onPick: (on) {
                      if (on) {
                        _askGs(p, tick: true).ignore();
                      } else {
                        _toggle(uuid, false);
                      }
                    },
                    onMeasure: () => _askGs(p, tick: false).ignore(),
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            // Room under the last row so the floating button never covers it.
            padding: EdgeInsets.fromLTRB(pad.left, 20, pad.right, pad.bottom + (showSend ? 88 : 0)),
            sliver: SliverToBoxAdapter(child: _History(docs: docs, projects: projects)),
          ),
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

/// One point on the checklist: the tick for "worked on that day", the
/// measured GS beside its design GS. Ticking or tapping opens the GS dialog;
/// nothing is typed in the row itself.
class _PileRow extends StatelessWidget {
  const _PileRow({
    required this.pile,
    required this.picked,
    required this.gs,
    required this.error,
    required this.measuredAt,
    required this.locked,
    required this.onPick,
    required this.onMeasure,
  });

  final Map<String, Object?> pile;
  final bool picked;
  final double? gs;
  final String? error;

  /// When this surveyor last saved a GS for the point; `null` = never.
  final DateTime? measuredAt;
  final bool locked;
  final ValueChanged<bool> onPick;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final design = toDoubleOrNull(pile['groundLevel']);
    final tip = toDoubleOrNull(pile['tipLevel']);
    final col = toDoubleOrNull(pile['cutOffLevel']);
    final dia = toIntOrNull(pile['diameterMm']);
    final meta = [
      if (dia != null && dia > 0) 'Ø$dia',
      if (col != null) 'COL ${formatElevation(col)}',
      if (tip != null) 'Tip ${formatElevation(tip)}',
    ].join('   ');
    final value = gs;
    return QuietPanel(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: locked ? null : onMeasure,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Checkbox(value: picked, onChanged: locked ? null : (v) => onPick(v ?? false)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 8, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${pile['code']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: w.ink)),
                      if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: 12, color: w.muted)),
                      if (measuredAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l.iplMeasuredAt(formatTime(measuredAt!)),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: w.okFg),
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(error!, style: TextStyle(fontSize: 12, color: w.badFg)),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value == null ? l.iplNotMeasured : formatElevation(value, decimals: 3),
                      style: value == null
                          ? TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: w.muted)
                          : TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: w.ink,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                    ),
                    if (design != null)
                      Text(
                        l.iplDesignShort(formatElevation(design, decimals: 3)),
                        style: TextStyle(fontSize: 12, color: w.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
