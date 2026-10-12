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

  static bool _inFilter(FieldPilePoint t, String filter) => switch (filter) {
        'undrilled' => t.stage == 'belum_bor' || t.stage == 'sedang_bor',
        'drilled' => t.stage == 'sudah_bor' || t.stage == 'berjalan',
        'cast' => t.stage == 'selesai' || t.stage == 'sudah_cor',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final data = ref.watch(fieldPilePointsProvider(widget.projectId));
    final project = (ref.watch(projectsProvider).value ?? const []).where((p) => '${p['id']}' == '${widget.projectId}').firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(project == null ? 'Titik bor' : '${project['code']} · titik bor')),
      floatingActionButton: _showTop
          ? FloatingActionButton.small(
              tooltip: 'Ke atas',
              onPressed: _toTop,
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
      body: data.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(title: 'Titik gagal dibaca', message: '$e'),
        data: (all) {
          final matching = _search.isEmpty
              ? all
              : all.where((t) => t.code.toLowerCase().contains(_search.toLowerCase())).toList();
          final items = matching.where((t) => _inFilter(t, _filter)).toList();
          final castCount = all.where((t) => t.stage == 'selesai' || t.stage == 'sudah_cor').length;

          if (all.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(Dimens.pagePadding),
              child: TerraBanner(
                kind: BannerKind.info,
                title: 'Belum ada titik bor',
                body: 'Titik bor diisi kantor (impor Excel di TerraBot web). Tarik ke bawah di halaman sebelumnya untuk mengambil yang terbaru.',
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
                          hintText: 'Cari kode titik',
                          suffixIcon: _search.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Hapus',
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
                            for (final (k, l) in const [
                              ('all', 'Semua'),
                              ('undrilled', 'Belum bor'),
                              ('drilled', 'Dibor'),
                              ('cast', 'Dicor'),
                            ]) ...[
                              ChoiceChip(
                                label: Text('$l (${matching.where((t) => _inFilter(t, k)).length})'),
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
                      child: Text('$castCount dari ${all.length} titik sudah dicor', style: TextStyle(color: w.muted)),
                    ),
                    if (items.isEmpty) const EmptyState(message: 'Tidak ada titik yang cocok.'),
                    for (final t in items) _card(t),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(FieldPilePoint t) {
    final w = context.colors;
    // Each stage its own colour, in the order of the work: grey → amber
    // (drilling) → blue (drilled) → purple (casting) → green (cast).
    final (text, bg, fg) = switch (t.stage) {
      'berjalan' => ('Sedang dicor', w.checkedBg, w.checkedFg),
      'selesai' || 'sudah_cor' => ('Sudah dicor', w.okBg, w.okFg),
      'sudah_bor' => ('Dibor ${formatMeters(t.drillDepthM)}', w.infoBg, w.infoFg),
      'sedang_bor' => ('Sedang dibor', w.warnBg, w.warnFg),
      _ => ('Belum dibor', w.surface2, w.muted),
    };
    final busy = t.stage == 'berjalan' || t.stage == 'sedang_bor';
    return ListCard(
      onTap: () => _showActions(t),
      // Work in progress stands out in a long list.
      edgeColor: busy ? fg : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.code, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: w.ink)),
                Text('D${t.diameterMm} · efektif ${formatMeters(t.plannedEffectiveLengthM)} · ${t.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ',')} m³',
                    style: TextStyle(color: w.muted, fontSize: 13)),
                if (t.groundLevel == null && t.stage != 'sudah_cor')
                  Text('GS belum diisi', style: TextStyle(color: w.warnFg, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          StatusBadge(text: text, bg: bg, fg: fg),
        ],
      ),
    );
  }

  Future<void> _showActions(FieldPilePoint t) async {
    final session = ref.read(sessionProvider).value;
    // Satu akun, satu HP: HP yang sudah digantikan dan lewat masa
    // tenggang hanya boleh mengirim sisa antreannya, tidak membuka
    // pekerjaan baru. Sebabnya terbaca di banner Beranda.
    final allows = ref.watch(canRecordProvider) && (session?.allows('field_casting', 'create') ?? false);
    final g = t.geometry;
    final w = context.colors;
    // The casting log needs the drilled depth: it sets the hole bottom that
    // the tremie, the concrete rise and the soundings are measured against.
    final drilled = t.isDrilled;
    final elsewhere = t.castedElsewhere && t.stage != 'sudah_cor';
    final drillLogOpen = t.drillLog != null && t.drillLogBody?['status'] != 'selesai';
    final drillingElsewhere = t.drillLoggedElsewhere && t.stage == 'sedang_bor';
    // The log is missing from THIS phone but the server says this very account
    // holds it (another phone of his, or a reinstall). Nobody can read a
    // handover code out to him, so he takes it back without one.
    final myId = session?.user?.id;
    final castingIsMine = myId != null && t.castingHolderId == myId;
    final drillLogIsMine = myId != null && t.drillLogHolderId == myId;
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
              Text('Titik ${t.code}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
              const SizedBox(height: 8),
              _InfoRow('Diameter', '${t.diameterMm} mm'),
              _InfoRow('GS / cut-off / tip', '${_elevation(t.groundLevel)} / ${_elevation(t.cutOffLevel)} / ${_elevation(t.tipLevel)}'),
              _InfoRow('Kedalaman cut-off dari GS', formatMeters(g?.cutOffDepthM)),
              _InfoRow('Panjang bor rencana', formatMeters(g?.plannedDrillLengthM)),
              _InfoRow('Panjang efektif rencana', formatMeters(t.plannedEffectiveLengthM)),
              _InfoRow('Volume teoritis rencana', '${t.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ',')} m³'),
              if (t.drillDepthM != null) _InfoRow('Kedalaman bor aktual', formatMeters(t.drillDepthM)),
              const SizedBox(height: 14),
              if (g == null && t.stage != 'sudah_cor')
                const TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.terrain_outlined,
                  title: 'Elevasi GS belum diisi',
                  body: 'Kedalaman dari GS belum dapat dihitung, dan log cor baru bisa dimulai setelah GS terisi. '
                      'Isi GS saat menandai titik ini sudah dibor.',
                ),
              if (elsewhere) ...[
                TerraBanner(
                  kind: BannerKind.warning,
                  icon: Icons.block,
                  title: !t.castingHeldElsewhere
                      ? 'Titik ini sudah punya log cor'
                      : castingIsMine
                          ? 'Log cornya ada di HP Anda yang lain'
                          : 'Sedang dicor dari HP lain',
                  body: !t.castingHeldElsewhere
                      ? '${t.castingHolderName ?? t.serverCastingBy ?? 'Rekan'} yang memegang log cornya. '
                          'Satu titik hanya boleh satu log cor. Bila log itu salah, minta kantor menghapusnya dulu.'
                      : castingIsMine
                          ? 'Log cor ini dipegang akun Anda sendiri, hanya isinya belum ada di HP ini. '
                              'Ambil langsung ke sini tanpa kode oper.'
                          : '${t.castingHolderName ?? t.serverCastingBy ?? 'Rekan'} yang memegang log cornya. '
                              'Satu titik hanya boleh satu log cor. Untuk melanjutkan dari HP ini, '
                              'minta dia menekan "Oper ke rekan" lalu masukkan kodenya di sini.',
                ),
                if (t.castingHeldElsewhere && allows && t.serverCastingUuid != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => castingIsMine
                        ? _resumeOwn(c, entity: 'casting', uuid: t.serverCastingUuid!, point: t)
                        : _redeem(c, entity: 'casting', uuid: t.serverCastingUuid!, point: t),
                    icon: Icon(castingIsMine ? Icons.phonelink_setup : Icons.swap_horiz),
                    label: Text(castingIsMine ? 'Ambil ke HP ini' : 'Lanjutkan di HP ini (kode oper)'),
                  ),
                ],
              ],
              if (drillingElsewhere) ...[
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.construction,
                  title: drillLogIsMine ? 'Log bornya ada di HP Anda yang lain' : 'Sedang dibor dari HP lain',
                  body: drillLogIsMine
                      ? 'Log bor ini dipegang akun Anda sendiri, hanya isinya belum ada di HP ini. '
                          'Ambil langsung ke sini tanpa kode oper.'
                      : 'Log bornya dipegang ${t.drillLogHolderName ?? t.serverDrillLogBy ?? 'rekan'}. '
                          'Satu titik hanya boleh satu log bor. Untuk melanjutkan dari HP ini, '
                          'minta dia menekan "Oper ke rekan" lalu masukkan kodenya di sini.',
                ),
                if (allows && t.serverDrillLogUuid != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => drillLogIsMine
                        ? _resumeOwn(c, entity: 'drill_log', uuid: t.serverDrillLogUuid!, point: t)
                        : _redeem(c, entity: 'drill_log', uuid: t.serverDrillLogUuid!, point: t),
                    icon: Icon(drillLogIsMine ? Icons.phonelink_setup : Icons.swap_horiz),
                    label: Text(drillLogIsMine ? 'Ambil ke HP ini' : 'Lanjutkan di HP ini (kode oper)'),
                  ),
                ],
              ]
              else if (!drilled && allows && !elsewhere)
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.straighten,
                  title: drillLogOpen ? 'Sedang dibor' : 'Catat bor dulu',
                  body: drillLogOpen
                      ? 'Log cor bisa dimulai setelah log bor ditutup dengan "Selesai bor".'
                      : 'Log cor baru bisa dimulai setelah titik ini selesai dibor: lewat log bor, atau tandai langsung.',
                ),
              if (!allows)
                const TerraBanner(kind: BannerKind.info, title: 'Hanya dapat dilihat', body: 'Akun ini tidak berhak mencatat log cor.')
              else ...[
                // Not drilled yet: drilling is THE next step, so it gets the
                // filled button and "Mulai log cor" below stays disabled.
                if (t.drillLog != null && drillLogOpen)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${t.drillLog!.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: const Text('Lanjutkan log bor'),
                  )
                else if (t.drillLog != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${t.drillLog!.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: const Text('Lihat log bor'),
                  )
                else if (!drilled && !drillingElsewhere) ...[
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/drilling/log/${newUuid()}?pilePoint=${t.uuid}');
                    },
                    icon: const Icon(Icons.construction),
                    label: const Text('Mulai log bor'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _markDrilled(t);
                    },
                    icon: const Icon(Icons.straighten),
                    label: const Text('Tandai sudah dibor (tanpa log)'),
                  ),
                ],
                if (t.stage == 'sudah_bor') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _markDrilled(t);
                    },
                    icon: const Icon(Icons.straighten),
                    label: const Text('Koreksi kedalaman bor / GS'),
                  ),
                ],
                const SizedBox(height: 10),
                if (t.casting != null)
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      context.push('/casting/log/${t.casting!.uuid}');
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Buka log cor'),
                  )
                else if (t.stage != 'sudah_cor' && !elsewhere)
                  FilledButton.icon(
                    onPressed: g == null || !drilled
                        ? null
                        : () {
                            Navigator.pop(c);
                            context.push('/casting/log/${newUuid()}?pilePoint=${t.uuid}');
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Mulai log cor'),
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
    final ok = await redeemHandoverFlow(context, ref, entity: entity, uuid: uuid, pointCode: point.code);
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
      v == null ? 'belum diisi' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2).replaceAll('.', ',')}';

  /// Mark drilled, with the ground level (GS) measured at the hole.
  ///
  /// GS is REQUIRED when the point has none yet: the casting log cannot start
  /// without it. When it is already known it is shown for correction and only
  /// sent if changed.
  Future<void> _markDrilled(FieldPilePoint t) async {
    final knownGs = t.groundLevel;
    final initialDepth = t.drillDepthM ?? t.geometry?.plannedDrillLengthM;
    // The dialog owns its text controllers: disposing them here, while the
    // dialog is still animating out, crashes ('_dependents.isEmpty').
    final result = await showDialog<({double depth, double? groundLevel})>(
      context: context,
      builder: (c) => _DrillDialog(
        code: t.code,
        initialDepth: initialDepth == null ? '' : initialDepth.toStringAsFixed(2).replaceAll('.', ','),
        initialGs: knownGs == null ? '' : knownGs.toStringAsFixed(3).replaceAll('.', ','),
        gsRequired: knownGs == null,
        cutOffLevel: t.cutOffLevel,
        tipLevel: t.tipLevel,
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
        'pilePointUuid': t.uuid,
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
            Expanded(child: Text('${t.code} ditandai sudah dibor ${formatMeters(result.depth)}.')),
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
      setState(() => _problem = 'Elevasi GS tidak sah.');
      return;
    }
    if (widget.gsRequired && gs == null) {
      setState(() => _problem = 'Isi elevasi GS titik ini. Log cor tidak dapat dimulai tanpanya.');
      return;
    }
    if (depth == null || depth <= 0) {
      setState(() => _problem = 'Isi kedalaman bor (m), lebih dari 0.');
      return;
    }
    if (depth > maxDrillDepthM) {
      setState(() => _problem = 'Kedalaman paling dalam ${formatMeters(maxDrillDepthM, decimals: 0)}. Periksa angkanya.');
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
      title: Text('Tandai dibor ${widget.code}', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (problem != null) ...[
              TerraBanner(kind: BannerKind.danger, title: 'Periksa isian', body: problem),
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
                labelText: widget.gsRequired ? 'Elevasi GS (m) — wajib' : 'Elevasi GS (m)',
                suffixText: 'm',
              ),
              onChanged: (_) => setState(() => _problem = null),
            ),
            if (cutOffAboveGs)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TerraBanner(
                  kind: BannerKind.warning,
                  title: 'Cut-off di atas GS',
                  body: 'COL ${formatElevation(widget.cutOffLevel)} lebih tinggi dari GS ini. '
                      'Pastikan angka GS benar sebelum menyimpan.',
                ),
              ),
            const SizedBox(height: 18),
            TextField(
              controller: _depthInput,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInput(maxIntDigits: 3),
              decoration: const InputDecoration(labelText: 'Kedalaman bor (m)', suffixText: 'm'),
              onChanged: (_) => setState(() => _problem = null),
            ),
            if (overPlan != null) ...[
              const SizedBox(height: 8),
              TerraBanner(
                kind: BannerKind.warning,
                title: 'Sudah lewat ${formatMeters(overPlan)} dari rencana',
                body: 'Rencana ${formatMeters(planned)}. Lewat sedikit boleh; pastikan memang perlu dibor lebih dalam.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: refusal == null ? _submit : null, child: const Text('Simpan')),
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
