import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/status_badge.dart';
import '../drilling/drill_readings.dart';
import 'handover.dart';
import 'level_reference.dart';
import 'pile_point_data.dart';
import '../../core/i18n.dart';

/// Pile points of one project.
class PilePointsPage extends ConsumerStatefulWidget {
  const PilePointsPage({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<PilePointsPage> createState() => _PilePointsPageState();
}

class _PilePointsPageState extends ConsumerState<PilePointsPage> {
  String _filter = 'all';
  String _search = '';
  final _searchInput = TextEditingController();

  /// The search and filter bar stays put above the list; "back to top"
  /// appears once the list has scrolled a screen or so.
  final _scroll = ScrollController();
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > 600;
      if (show != _showTop) setState(() => _showTop = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchInput.dispose();
    super.dispose();
  }

  void _toTop() => _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  /// New search or filter: show the result from its first item.
  void _jumpTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  static bool _inFilter(FieldPilePoint pt, String filter) => switch (filter) {
        'undrilled' => pt.stage == 'belum_bor' || pt.stage == 'sedang_bor',
        'drilled' => pt.stage == 'sudah_bor' || pt.stage == 'berjalan',
        'cast' => pt.stage == 'selesai' || pt.stage == 'sudah_cor',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final data = ref.watch(fieldPilePointsProvider(widget.projectId));
    final project = (ref.watch(projectsProvider).value ?? const []).where((p) => '${p['id']}' == '${widget.projectId}').firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(project == null ? t(context).pointsTitle : t(context).pointsTitleOf('${project['code']}'))),
      floatingActionButton: _showTop
          ? FloatingActionButton.small(
              tooltip: t(context).toTop,
              onPressed: _toTop,
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
      body: data.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(title: t(context).pointsLoadError, message: '$e'),
        data: (all) {
          final matching = _search.isEmpty
              ? all
              : all.where((pt) => pt.code.toLowerCase().contains(_search.toLowerCase())).toList();
          final items = matching.where((pt) => _inFilter(pt, _filter)).toList();
          final castCount = all.where((pt) => pt.stage == 'selesai' || pt.stage == 'sudah_cor').length;

          if (all.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(Dimens.pagePadding),
              child: TerraBanner(
                kind: BannerKind.info,
                title: t(context).noPointsTitle,
                body: t(context).noPointsBody,
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sticky: search and filters never scroll away.
              Material(
                color: w.pageBg,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 12, Dimens.pagePadding, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _searchInput,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: t(context).searchPointCode,
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: t(context).clear,
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchInput.clear();
                                    setState(() => _search = '');
                                    _jumpTop();
                                  },
                                ),
                        ),
                        onChanged: (v) {
                          setState(() => _search = v.trim());
                          _jumpTop();
                        },
                      ),
                      const SizedBox(height: 8),
                      // One scrolling row of chips, each with its count.
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final (k, l) in [
                              ('all', t(context).filterAll),
                              ('undrilled', t(context).filterUndrilled),
                              ('drilled', t(context).filterDrilled),
                              ('cast', t(context).filterCast),
                            ]) ...[
                              ChoiceChip(
                                label: Text('$l (${matching.where((pt) => _inFilter(pt, k)).length})'),
                                selected: _filter == k,
                                onSelected: (_) {
                                  setState(() => _filter = k);
                                  _jumpTop();
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: w.line),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 12, Dimens.pagePadding, 80),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(t(context).castProgress(castCount, all.length), style: TextStyle(color: w.muted)),
                    ),
                    if (items.isEmpty) EmptyState(message: t(context).noMatchingPoints),
                    for (final pt in items) _card(pt),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(FieldPilePoint pt) {
    final w = context.colors;
    // Each stage its own colour, in the order of the work: grey → amber
    // (drilling) → blue (drilled) → purple (casting) → green (cast).
    final (text, bg, fg) = switch (pt.stage) {
      'berjalan' => (t(context).stageCasting, w.checkedBg, w.checkedFg),
      'selesai' || 'sudah_cor' => (t(context).stageCast, w.okBg, w.okFg),
      'sudah_bor' => (t(context).stageDrilled(formatMeters(pt.drillDepthM)), w.infoBg, w.infoFg),
      'sedang_bor' => (t(context).stageDrilling, w.warnBg, w.warnFg),
      _ => (t(context).stageUndrilled, w.surface2, w.muted),
    };
    final busy = pt.stage == 'berjalan' || pt.stage == 'sedang_bor';
    return ListCard(
      onTap: () => _showActions(pt),
      // Work in progress stands out in a long list.
      edgeColor: busy ? fg : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pt.code, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                Text('D${pt.diameterMm} · efektif ${formatMeters(pt.plannedEffectiveLengthM)} · ${pt.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ',')} m³',
                    style: TextStyle(color: w.muted, fontSize: 13)),
                if (pt.groundLevel == null && pt.stage != 'sudah_cor')
                  Text(t(context).gsMissingShort, style: TextStyle(color: w.warnFg, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          StatusBadge(text: text, bg: bg, fg: fg),
        ],
      ),
    );
  }

  Future<void> _showActions(FieldPilePoint pt) async {
    final session = ref.read(sessionProvider).value;
    // Satu akun, satu HP: HP yang sudah digantikan dan lewat masa
    // tenggang hanya boleh mengirim sisa antreannya, tidak membuka
    // pekerjaan baru. Sebabnya terbaca di banner Beranda.
    final allows = ref.watch(canRecordProvider) && (session?.allows('field_casting', 'create') ?? false);
    final g = pt.geometry;
    final w = context.colors;
    // The casting log needs the drilled depth: it sets the hole bottom that
    // the tremie, the concrete rise and the soundings are measured against.
    final drilled = pt.isDrilled;
    final elsewhere = pt.castedElsewhere && pt.stage != 'sudah_cor';
    final drillLogOpen = pt.drillLog != null && pt.drillLogBody?['status'] != 'selesai';
    final drillingElsewhere = pt.drillLoggedElsewhere && pt.stage == 'sedang_bor';
    // The log is missing from THIS phone but the server says this very account
    // holds it (another phone of his, or a reinstall). Nobody can read a
    // handover code out to him, so he takes it back without one.
    final myId = session?.user?.id;
    final castingIsMine = myId != null && pt.castingHolderId == myId;
    final drillLogIsMine = myId != null && pt.drillLogHolderId == myId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t(context).pointHeading(pt.code), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
              const SizedBox(height: 8),
              _InfoRow(t(context).fieldDiameter, '${pt.diameterMm} mm'),
              _InfoRow(t(context).fieldLevels, '${_elevation(pt.groundLevel)} / ${_elevation(pt.cutOffLevel)} / ${_elevation(pt.tipLevel)}'),
              _InfoRow(t(context).fieldCutOffDepth, formatMeters(g?.cutOffDepthM)),
              _InfoRow(t(context).fieldPlannedDrill, formatMeters(g?.plannedDrillLengthM)),
              _InfoRow(t(context).fieldPlannedEff, formatMeters(pt.plannedEffectiveLengthM)),
              _InfoRow(t(context).fieldPlannedVol, '${pt.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ',')} m³'),
              if (pt.drillDepthM != null) _InfoRow(t(context).fieldActualDrill, formatMeters(pt.drillDepthM)),
              const SizedBox(height: 14),
              if (g == null && pt.stage != 'sudah_cor')
                TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.terrain_outlined,
                  title: t(context).gsMissingTitle,
                  body: t(context).gsMissingBody,
                ),
              if (elsewhere) ...[
                TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.block,
                  title: !pt.castingHeldElsewhere
                      ? t(context).castLogExists
                      : castingIsMine
                          ? t(context).castLogOnMyOther
                          : t(context).castLogElsewhere,
                  body: !pt.castingHeldElsewhere
                      ? t(context).castLogHeldBody(pt.castingHolderName ?? pt.serverCastingBy ?? t(context).colleague)
                      : castingIsMine
                          ? t(context).logIsMineBody
                          : t(context).castLogHandoverBody(pt.castingHolderName ?? pt.serverCastingBy ?? t(context).colleague),
                ),
                if (pt.castingHeldElsewhere && allows && pt.serverCastingUuid != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => castingIsMine
                        ? _resumeOwn(c, entity: 'casting', uuid: pt.serverCastingUuid!, point: pt)
                        : _redeem(c, entity: 'casting', uuid: pt.serverCastingUuid!, point: pt),
                    icon: Icon(castingIsMine ? Icons.phonelink_setup : Icons.swap_horiz),
                    label: Text(castingIsMine ? t(context).takeToThisPhone : t(context).continueHereCode),
                  ),
                ],
              ],
              if (drillingElsewhere) ...[
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.construction,
                  title: drillLogIsMine ? t(context).drillLogOnMyOther : t(context).drillLogElsewhere,
                  body: drillLogIsMine
                      ? t(context).logIsMineBody
                      : t(context).drillLogHandoverBody(pt.drillLogHolderName ?? pt.serverDrillLogBy ?? t(context).colleague),
                ),
                if (allows && pt.serverDrillLogUuid != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => drillLogIsMine
                        ? _resumeOwn(c, entity: 'drill_log', uuid: pt.serverDrillLogUuid!, point: pt)
                        : _redeem(c, entity: 'drill_log', uuid: pt.serverDrillLogUuid!, point: pt),
                    icon: Icon(drillLogIsMine ? Icons.phonelink_setup : Icons.swap_horiz),
                    label: Text(drillLogIsMine ? t(context).takeToThisPhone : t(context).continueHereCode),
                  ),
                ],
              ]
              else if (!drilled && allows && !elsewhere)
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.straighten,
                  title: drillLogOpen ? t(context).stageDrilling : t(context).drillFirstTitle,
                  body: drillLogOpen ? t(context).castAfterDrillLog : t(context).castAfterDrilled,
                ),
              if (!allows)
                TerraBanner(kind: BannerKind.info, title: t(context).viewOnlyTitle, body: t(context).viewOnlyCastBody)
              else ...[
                // Not drilled yet: drilling is THE next step, so it gets the
                // filled button and "Mulai log cor" below stays disabled.
                if (pt.drillLog != null && drillLogOpen)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${pt.drillLog!.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: Text(t(context).continueDrillLog),
                  )
                else if (pt.drillLog != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${pt.drillLog!.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: Text(t(context).viewDrillLog),
                  )
                else if (!drilled && !drillingElsewhere) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${newUuid()}?pilePoint=${pt.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: Text(t(context).startDrillLog),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _markDrilled(pt);
                    },
                    icon: const Icon(Icons.straighten),
                    label: Text(t(context).markDrilledNoLog),
                  ),
                ],
                if (pt.stage == 'sudah_bor') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _markDrilled(pt);
                    },
                    icon: const Icon(Icons.straighten),
                    label: Text(t(context).correctDrillGs),
                  ),
                ],
                const SizedBox(height: 10),
                if (pt.casting != null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/casting/log/${pt.casting!.uuid}');
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: Text(t(context).openCastLog),
                  )
                else if (pt.stage != 'sudah_cor' && !elsewhere)
                  FilledButton.icon(
                    onPressed: g == null || !drilled
                        ? null
                        : () {
                            Navigator.pop(c);
                            context.push('/casting/log/${newUuid()}?pilePoint=${pt.uuid}');
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(t(context).startCastLog),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Type the handover code on a locked point; on success the log is on this
  /// phone and its screen opens.
  Future<void> _redeem(BuildContext sheet, {required String entity, required String uuid, required FieldPilePoint point}) async {
    final ok = await redeemHandoverFlow(
      context,
      ref,
      entity: entity,
      uuid: uuid,
      pointCode: point.code,
      holderName: entity == 'drill_log'
          ? point.drillLogHolderName ?? point.serverDrillLogBy
          : point.castingHolderName ?? point.serverCastingBy,
    );
    if (!ok || !mounted) return;
    if (sheet.mounted) Navigator.pop(sheet);
    // Not awaited on purpose: this returns only when the log screen is
    // popped again, and nothing here depends on that.
    unawaited(context.push(entity == 'drill_log' ? '/drilling/log/$uuid' : '/casting/log/$uuid'));
  }

  /// Same, for a log this very account already holds: no code is asked.
  Future<void> _resumeOwn(BuildContext sheet, {required String entity, required String uuid, required FieldPilePoint point}) async {
    final ok = await resumeOwnLogFlow(context, ref, entity: entity, uuid: uuid, pointCode: point.code);
    if (!ok || !mounted) return;
    if (sheet.mounted) Navigator.pop(sheet);
    unawaited(context.push(entity == 'drill_log' ? '/drilling/log/$uuid' : '/casting/log/$uuid'));
  }

  String _elevation(double? v) =>
      v == null ? t(context).notFilled : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Mark drilled, with the ground level (GS) measured at the hole.
  ///
  /// GS is REQUIRED when the point has none yet: the casting log cannot start
  /// without it. When it is already known it is shown for correction and only
  /// sent if changed.
  Future<void> _markDrilled(FieldPilePoint pt) async {
    final knownGs = pt.groundLevel;
    final initialDepth = pt.drillDepthM ?? pt.geometry?.plannedDrillLengthM;
    // The dialog owns its text controllers: disposing them here, while the
    // dialog is still animating out, crashes ('_dependents.isEmpty').
    final result = await showDialog<({double depth, double? groundLevel})>(
      context: context,
      builder: (c) => _DrillDialog(
        code: pt.code,
        initialDepth: initialDepth == null ? '' : initialDepth.toStringAsFixed(2).replaceAll('.', ','),
        initialGs: knownGs == null ? '' : knownGs.toStringAsFixed(3).replaceAll('.', ','),
        gsRequired: knownGs == null,
        cutOffLevel: pt.cutOffLevel,
        tipLevel: pt.tipLevel,
      ),
    );
    if (result == null) return;
    final p = ref.read(userProvider);
    if (p == null) return;
    final gs = result.groundLevel;
    final sendGs = gs != null && (knownGs == null || (gs - knownGs).abs() > 0.0005);
    await ref.read(dbProvider).saveDocument(
      uuid: newUuid(),
      entity: 'drill_mark',
      userId: p.id,
      body: {
        'pilePointUuid': pt.uuid,
        'drilledDepthM': decimalText(result.depth),
        'at': isoWithOffset(DateTime.now()),
        if (sendGs) 'groundLevel': decimalText(gs, decimals: 3),
      },
    );
    ref.read(syncProvider.notifier).afterSave();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(t(context).markedDrilled(pt.code, formatMeters(result.depth)))),
          ],
        ),
      ),
    );
  }
}

class _DrillDialog extends StatefulWidget {
  const _DrillDialog({
    required this.code,
    required this.initialDepth,
    required this.initialGs,
    required this.gsRequired,
    required this.cutOffLevel,
    required this.tipLevel,
  });

  final String code;
  final String initialDepth;
  final String initialGs;
  final bool gsRequired;
  final double cutOffLevel;
  final double tipLevel;

  @override
  State<_DrillDialog> createState() => _DrillDialogState();
}

class _DrillDialogState extends State<_DrillDialog> {
  late final _depthInput = TextEditingController(text: widget.initialDepth);
  late final _gsInput = TextEditingController(text: widget.initialGs);
  String? _problem;

  double? _plannedFor(double? gs) => gs == null ? null : gs - widget.tipLevel;

  @override
  void dispose() {
    _depthInput.dispose();
    _gsInput.dispose();
    super.dispose();
  }


  void _submit() {
    final depth = parseNumber(_depthInput.text);
    final gsText = _gsInput.text.trim();
    final gs = gsText.isEmpty ? null : parseNumber(gsText);
    if (gsText.isNotEmpty && (gs == null || gs < -500 || gs > 5000)) {
      setState(() => _problem = t(context).gsInvalid);
      return;
    }
    if (widget.gsRequired && gs == null) {
      setState(() => _problem = t(context).gsRequiredMsg);
      return;
    }
    if (depth == null || depth <= 0) {
      setState(() => _problem = t(context).drillDepthInvalid);
      return;
    }
    if (depth > maxDrillDepthM) {
      setState(() => _problem = t(context).drillDepthTooDeep(formatMeters(maxDrillDepthM, decimals: 0)));
      return;
    }
    final planned = _plannedFor(gs);
    if (planned != null && farBeyondPlan(depth, planned)) {
      setState(() => _problem = farBeyondPlanText(depth, planned));
      return;
    }
    Navigator.pop(context, (depth: depth, groundLevel: gs));
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final typedGs = parseNumber(_gsInput.text);
    final typedDepth = parseNumber(_depthInput.text);
    final planned = _plannedFor(typedGs);
    // A depth that can never be saved: red banner and a disabled button.
    final refusal = depthRefusal(typedDepth, planned);
    final problem = _problem ?? refusal;
    final overPlan = typedDepth == null || refusal != null ? null : beyondPlanM(typedDepth, planned);
    final cutOffAboveGs = typedGs != null && typedGs < widget.cutOffLevel;
    return AlertDialog(
      icon: Icon(Icons.straighten, size: 32, color: w.brand),
      title: Text(t(context).markDrilledTitle(widget.code), textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (problem != null) ...[
              TerraBanner(kind: BannerKind.danger, title: t(context).checkInput, body: problem),
              const SizedBox(height: 8),
            ],
            LevelReferenceBanner(
              cutOffLevel: widget.cutOffLevel,
              tipLevel: widget.tipLevel,
              groundLevel: typedGs,
            ),
            // Room for the floating label, which sits ON the field's top border.
            const SizedBox(height: 16),
            TextField(
              controller: _gsInput,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: decimalInput(maxIntDigits: 4, decimals: 3, signed: true),
              decoration: InputDecoration(
                labelText: widget.gsRequired ? t(context).gsFieldRequired : t(context).gsField,
                suffixText: 'm',
              ),
              onChanged: (_) => setState(() => _problem = null),
            ),
            if (cutOffAboveGs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TerraBanner(
                  kind: BannerKind.warning,
                  title: t(context).cutOffAboveGsTitle,
                  body: t(context).cutOffAboveGsBody(formatElevation(widget.cutOffLevel)),
                ),
              ),
            const SizedBox(height: 18),
            TextField(
              controller: _depthInput,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInput(maxIntDigits: 3),
              decoration: InputDecoration(labelText: t(context).drillDepthField, suffixText: 'm'),
              onChanged: (_) => setState(() => _problem = null),
            ),
            if (overPlan != null) ...[
              const SizedBox(height: 8),
              TerraBanner(
                kind: BannerKind.warning,
                title: t(context).beyondPlanTitle(formatMeters(overPlan)),
                body: t(context).beyondPlanBody(formatMeters(planned)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t(context).cancel)),
        FilledButton(onPressed: refusal == null ? _submit : null, child: Text(t(context).save)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: w.muted))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: w.ink)),
        ],
      ),
    );
  }
}
