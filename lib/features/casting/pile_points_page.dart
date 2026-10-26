import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/decimal_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/confirm_code.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/widgets/list_card.dart';
import '../../core/widgets/view_states.dart';
import '../../core/widgets/status_badge.dart';
import '../drilling/drill_readings.dart';
import '../drilling/koordinat_aktual.dart';
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

  /// Keping saringan.
  ///
  /// `drilling` dan `casting` SENGAJA bertumpang dengan tiga keping lama —
  /// titik yang sedang dibor juga "belum dibor", dan yang sedang dicor juga
  /// "sudah dibor". Keduanya menjawab pertanyaan yang berbeda: tiga keping
  /// lama menanyakan SUDAH SAMPAI MANA lubangnya, dua keping baru
  /// menanyakan ADA YANG SEDANG MENGERJAKANNYA SEKARANG. Dipaksa saling
  /// meniadakan, "belum dibor" akan kehilangan titik yang rignya justru
  /// sedang berdiri di sana.
  ///
  /// Diminta Daniel, 20 Oktober 2026.
  static bool _inFilter(FieldPilePoint pt, String filter) => switch (filter) {
        'undrilled' => pt.stage == 'belum_bor' || pt.stage == 'sedang_bor',
        'drilled' => pt.stage == 'sudah_bor' || pt.stage == 'berjalan',
        'cast' => pt.stage == 'selesai' || pt.stage == 'sudah_cor',
        'drilling' => pt.stage == 'sedang_bor',
        'casting' => pt.stage == 'berjalan',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final data = ref.watch(fieldPilePointsProvider(widget.projectId));
    final project = (ref.watch(projectsProvider).value ?? const []).where((p) => '${p['id']}' == '${widget.projectId}').firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(project == null ? t(context).pointsTitle : t(context).pointsTitleOf('${project['code']}')),
        actions: [
          // DENAH: gambar berskala keadaan seluruh titik. Di bilah atas,
          // bukan di bawah daftar — yang membukanya mencari gambar, bukan
          // menggulir seratus baris untuk menemukannya.
          IconButton(
            tooltip: t(context).denahTitle,
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/casting/project/${widget.projectId}/denah'),
          ),
        ],
      ),
      floatingActionButton: _showTop
          ? FloatingActionButton.small(
              tooltip: t(context).toTop,
              onPressed: _toTop,
              child: const Icon(Icons.keyboard_arrow_up),
            )
          : null,
      body: data.when(
        loading: () => const SkeletonCards(),
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
                              // Yang SEDANG dikerjakan ditaruh tepat di
                              // sebelah keadaan lubangnya, bukan di ujung:
                              // yang mencari "siapa yang lagi kerja
                              // sekarang" tidak menggulir sampai habis
                              // untuk menemukannya.
                              ('drilling', t(context).filterDrilling),
                              ('drilled', t(context).filterDrilled),
                              ('casting', t(context).filterCasting),
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
                child: RefreshIndicator(
                  // Menarik daftar = tarik ulang dari server. Yang paling
                  // dicari di layar ini justru keadaan TERKINI titik yang
                  // sedang dikerjakan HP lain, dan menunggu sinkron berkala
                  // 15 menit untuk itu terasa seperti aplikasinya menggantung.
                  onRefresh: () => ref.read(syncProvider.notifier).run(diminta: true),
                  // DIBANGUN MALAS, bukan sekaligus.
                  //
                  // `ListView(children: [...])` membangun SELURUH kartu
                  // sebelum satu pun terlihat. Dinding R501 berisi 744
                  // titik, jadi setiap kali layar ini digambar ulang —
                  // mengetik di kotak cari, menekan keping saringan,
                  // sinkron selesai — 744 pohon widget dirakit untuk
                  // menampilkan sekitar sepuluh. `.builder` merakit yang
                  // terlihat saja.
                  child: ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 12, Dimens.pagePadding, 80),
                  // Butir 0 selalu baris kemajuan. Daftar kosong menambah
                  // satu butir lagi untuk keterangannya, bukan membiarkan
                  // layar kosong tanpa kata.
                  itemCount: items.isEmpty ? 2 : items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(t(context).castProgress(castCount, all.length), style: TextStyle(color: w.muted)),
                      );
                    }
                    if (items.isEmpty) {
                      return EmptyState(message: t(context).noMatchingPoints);
                    }
                    final k = i - 1;
                    final kartu = _card(items[k]);
                    // Animasi masuk HANYA untuk yang terlihat saat daftarnya
                    // dibuka. Dibiarkan pada semua butir, tiap kartu akan
                    // memudar masuk saat digulir melewatinya — dan pada
                    // guliran cepat itu terbaca sebagai layar yang
                    // tersendat, bukan sebagai sambutan.
                    //
                    // `AppearIn` sendiri sudah membatasi jedanya pada lima
                    // butir pertama, jadi di luar itu tidak ada yang hilang.
                    return k < _butirBeranimasi ? AppearIn(order: k, child: kartu) : kartu;
                  },
                ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Sebanyak kartu yang muat di satu layar — selebihnya tidak dianimasikan.
  static const _butirBeranimasi = 12;

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
                Text('D${pt.diameterMm} · efektif ${formatMeters(pt.plannedEffectiveLengthM)} · ${formatVolume(pt.plannedTheoreticalVolumeM3)}',
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

  /// Tarik ulang dari server lalu bangun ulang lembar ini di tempat.
  ///
  /// Tanpa ini, satu-satunya cara melihat kemajuan terbaru adalah menutup
  /// lembarnya, menarik daftarnya, lalu membukanya lagi — tiga langkah untuk
  /// satu pertanyaan yang ditanyakan berkali-kali dalam sehari.
  /// Tarik dari server. TIDAK membangun ulang lembarnya sendiri: lembarnya
  /// berlangganan lewat `Consumer`, jadi ia memperbarui diri begitu datanya
  /// benar-benar sampai.
  ///
  /// Dulu di sini ada `ulang(() {})` sesudah `run()`. Itu membangun ulang
  /// lembar SEBELUM stream drift mengantar baris barunya — jadi lembarnya
  /// digambar ulang dengan data lama, dan karena `ref.read` tidak
  /// berlangganan apa pun, ia tidak pernah dibangun ulang lagi ketika
  /// datanya tiba. Tombol muat ulang tampak tidak melakukan apa-apa, dan
  /// titik yang dikerjakan HP lain menampilkan pemegang serta kemajuan yang
  /// sudah basi sampai lembarnya ditutup dan dibuka lagi.
  Future<void> _segarkanLembar() async {
    await ref.read(syncProvider.notifier).run(diminta: true);
  }

  Future<void> _showActions(FieldPilePoint awal) async {
    final session = ref.read(sessionProvider).value;
    // Satu akun, satu HP: HP yang sudah digantikan dan lewat masa
    // tenggang hanya boleh mengirim sisa antreannya, tidak membuka
    // pekerjaan baru. Sebabnya terbaca di banner Beranda.
    final bolehCatat = ref.watch(canRecordProvider) && (session?.allows('field_casting', 'create') ?? false);
    final w = context.colors;
    // The log is missing from THIS phone but the server says this very account
    // holds it (another phone of his, or a reinstall). Nobody can read a
    // handover code out to him, so he takes it back without one.
    final myId = session?.user?.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => Consumer(
        builder: (c, ref, _) {
          // Titik DIAWASI, bukan dibaca sekali: sesudah sinkron, pemegang dan
          // angka kemajuannya ikut baru tanpa lembarnya perlu ditutup.
          final pt = (ref.watch(fieldPilePointsProvider(widget.projectId)).value ?? const <FieldPilePoint>[])
                  .where((x) => x.uuid == awal.uuid)
                  .firstOrNull ??
              awal;
          // Titik yang sudah dikonfirmasi kantor hanya boleh DIBACA. Server
          // menolak seluruh kirimannya; membiarkan tombolnya hidup di sini
          // berarti QS bekerja setengah jam lalu menemukan dokumennya merah
          // di antrean, dengan sebab yang tidak dapat ia perbaiki sendiri.
          final allows = bolehCatat && !pt.isChecked;
          final g = pt.geometry;
          final drilled = pt.isDrilled;
          final elsewhere = pt.castedElsewhere && pt.stage != 'sudah_cor';
          final drillLogOpen = pt.drillLog != null && pt.drillLogBody?['status'] != 'selesai';
          final drillingElsewhere = pt.drillLoggedElsewhere && pt.stage == 'sedang_bor';
          final castingIsMine = myId != null && pt.castingHolderId == myId;
          final drillLogIsMine = myId != null && pt.drillLogHolderId == myId;
          return SafeArea(
            // Isinya DIGULIR, dan tingginya dibatasi 85% layar.
            //
            // Tanpa ini, titik yang banner dan tombolnya panjang — sedang
            // dibor orang lain, GS kosong, plus kartu kemajuan — terpotong
            // di bawah tanpa ada tanda apa pun bahwa masih ada isi. Yang
            // hilang justru tombol-tombolnya, jadi layarnya tampak rusak.
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
              child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(t(context).pointHeading(pt.code),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
                  ),
                  IconButton(
                    tooltip: t(context).refresh,
                    onPressed: _segarkanLembar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
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
              if (pt.isChecked)
                TerraBanner(
                  kind: BannerKind.ok,
                  icon: Icons.verified,
                  title: t(context).pointConfirmedTitle,
                  body: t(context).pointConfirmedBody(
                    pt.checkedByName ?? t(context).colleague,
                    '${longDate(pt.checkedAt!)} ${formatTime(pt.checkedAt!)}',
                  ),
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
                _KemajuanCard(
                  label: t(context).castProgressLabel,
                  utama: pt.castingTruckCount == null || pt.castingTruckCount == 0
                      ? null
                      : t(context).castProgressMain(
                          '${pt.castingTruckCount}',
                          (pt.castingVolumeM3 ?? 0).toStringAsFixed(2).replaceAll('.', ','),
                          pt.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ','),
                        ),
                  rasio: pt.plannedTheoreticalVolumeM3 < 0.01
                      ? null
                      : ((pt.castingVolumeM3 ?? 0) / pt.plannedTheoreticalVolumeM3).clamp(0.0, 1.0),
                  kapan: pt.castingLastAt,
                  berjalan: pt.stage == 'berjalan',
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
                _KemajuanCard(
                  label: t(context).drillProgressLabel,
                  utama: pt.drillLogDeepestM == null
                      ? null
                      : t(context).drillProgressMain(
                          formatMeters(pt.drillLogDeepestM),
                          formatMeters(g?.plannedDrillLengthM),
                        ),
                  rasio: g == null || g.plannedDrillLengthM < 0.01
                      ? null
                      : ((pt.drillLogDeepestM ?? 0) / g.plannedDrillLengthM).clamp(0.0, 1.0),
                  kapan: pt.drillLogLastAt,
                  berjalan: pt.stage == 'sedang_bor',
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
              ],
              // Titik yang SUDAH selesai dicor oleh HP lain: lognya tidak ada
              // di sini dan tidak akan pernah ada, jadi tanpa ringkasan ini
              // layarnya cuma menampilkan angka rencana — orang tahu titiknya
              // sudah dicor tetapi tidak bisa melihat satu pun angka hasilnya.
              //
              // SUDAH SELESAI DAN SEDANG BERJALAN ADALAH DUA KARTU BERBEDA.
              //
              // Yang selesai dulu memakai kartu kemajuan yang sama: judulnya
              // "Kemajuan cor", angkanya "TM ke-4", dan bilah kemajuan serta
              // "catatan terakhir 1 hari lalu" di bawahnya. Ketiganya bahasa
              // sesuatu yang MASIH BERJALAN — padahal betonnya sudah
              // mengeras kemarin, dan "terakhir 1 hari lalu" terbaca sebagai
              // HP yang tertinggal mengirim, bukan sebagai pekerjaan yang
              // memang sudah usai.
              if (pt.casting == null && (pt.castingTruckCount ?? 0) > 0 && !elsewhere)
                if (pt.stage == 'sudah_cor')
                  _SelesaiCorCard(point: pt)
                else
                  _KemajuanCard(
                    label: t(context).castProgressLabel,
                    utama: t(context).castProgressMain(
                      '${pt.castingTruckCount}',
                      (pt.castingVolumeM3 ?? 0).toStringAsFixed(2).replaceAll('.', ','),
                      pt.plannedTheoreticalVolumeM3.toStringAsFixed(2).replaceAll('.', ','),
                    ),
                    rasio: pt.plannedTheoreticalVolumeM3 < 0.01
                        ? null
                        : ((pt.castingVolumeM3 ?? 0) / pt.plannedTheoreticalVolumeM3).clamp(0.0, 1.0),
                    kapan: pt.castingLastAt,
                    berjalan: pt.stage == 'berjalan',
                  ),
              // JARAK SEBELUM BANNER INI, bukan sesudah tombol di atasnya.
              //
              // Dilaporkan Daniel, 20 Okt 2026: tombol "Lanjutkan di HP ini
              // (kode oper)" menempel pada banner "Catat bor dulu".
              // Jaraknya ditaruh di sini supaya ia ikut muncul dan hilang
              // bersama bannernya — dipasang sesudah tombolnya, ia akan
              // menyisakan ruang kosong menggantung pada titik yang tidak
              // punya banner ini.
              if (!drilled && allows && !elsewhere) ...[
                const SizedBox(height: 10),
                TerraBanner(
                  kind: BannerKind.info,
                  icon: Icons.straighten,
                  title: drillLogOpen ? t(context).stageDrilling : t(context).drillFirstTitle,
                  body: drillLogOpen ? t(context).castAfterDrillLog : t(context).castAfterDrilled,
                ),
              ],
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
                    // Nomor titiknya diketik ulang dulu, sama seperti
                    // sebelum mulai cor. Salah tap baris di daftar tidak
                    // membedakan bor dan cor: yang membedakan hanya akibatnya
                    // — log bor yang salah titik membuat kedalaman satu
                    // lubang tercatat di lubang sebelahnya, dan dari situ
                    // seluruh hitungan tertanam serta volume tiang itu
                    // berdiri di atas angka yang bukan miliknya.
                    onPressed: () async {
                      final semua = (ref.read(fieldPilePointsProvider(widget.projectId)).value ?? const [])
                          .map((e) => e.code);
                      final benar = await askCodeConfirm(context, code: pt.code, allCodes: semua);
                      if (!benar || !mounted || !c.mounted) return;
                      Navigator.pop(c);
                      unawaited(
                        context.push(
                          '/drilling/log/${newUuid()}?pilePoint=${pt.uuid}',
                        ),
                      );
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
                    // Nomor titiknya diketik ulang dulu. Salah tap baris di
                    // daftar inilah yang pernah membuat cor satu titik
                    // tercatat di titik sebelahnya, dan baru ketahuan setelah
                    // angkanya ikut terhitung di volume. Lihat askCodeConfirm.
                    onPressed: g == null || !drilled
                        ? null
                        : () async {
                            final semua = (ref.read(fieldPilePointsProvider(widget.projectId)).value ?? const [])
                                .map((e) => e.code);
                            final benar = await askCodeConfirm(context, code: pt.code, allCodes: semua);
                            // DUA pemeriksaan mounted, dan keduanya perlu —
                            // tetapi masing-masing pada JENIS yang benar.
                            //
                            // `context` di sini milik State-nya, dan untuk
                            // itu yang sah adalah `mounted` milik State,
                            // bukan `context.mounted`. Analyzer menyebut
                            // yang kedua "unrelated mounted check" dan
                            // menolaknya lewat use_build_context_synchronously
                            // — benar, sebab `context.mounted` hanya
                            // menyatakan elemennya masih terpasang, bukan
                            // bahwa State yang memakainya masih hidup.
                            //
                            // `c` milik lembar bawah dan dipakai
                            // `Navigator.pop`, jadi ia diperiksa sendiri.
                            if (!benar || !mounted || !c.mounted) return;
                            Navigator.pop(c);
                            // `unawaited`: badan ini `async`, dan
                            // `analysis_options.yaml` menyalakan
                            // `unawaited_futures`. Lihat pemakaian yang sama
                            // di bawah pada _bukaLog.
                            unawaited(
                              context.push(
                                '/casting/log/${newUuid()}?pilePoint=${pt.uuid}',
                              ),
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: Text(t(context).startCastLog),
                  ),
              ],
              // Riwayat penuh dari server: satu-satunya cara melihat angka
              // log cor yang dibuat HP lain, termasuk titik yang sudah selesai
              // dicor berminggu-minggu lalu dan lognya tidak akan pernah
              // turun ke HP ini.
              if (pt.serverId != null &&
                  (pt.casting != null ||
                      pt.serverCastingUuid != null ||
                      (pt.castingTruckCount ?? 0) > 0 ||
                      pt.stage == 'sudah_cor')) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    context.push(
                      '/casting/point/${pt.serverId}/history?code=${Uri.encodeComponent(pt.code)}',
                    );
                  },
                  icon: const Icon(Icons.history),
                  label: Text(t(context).pointHistoryOpen),
                ),
              ],

              // PANTAU — hanya selagi pekerjaannya BERJALAN.
              //
              // Diminta Daniel, 18 Okt 2026. Dipisah dari "Lihat riwayat":
              // riwayat menjawab "apa yang sudah terjadi", pantau menjawab
              // "sampai mana sekarang". Ditawarkan pada titik yang sudah
              // selesai, ia hanya menggambar keadaan akhir yang tidak akan
              // berubah lagi — dan tombol yang menjanjikan gerak lalu diam
              // membuat orang menyimpulkan layarnya rusak.
              if (pt.serverId != null &&
                  pt.casting == null &&
                  pt.stage != 'sudah_cor' &&
                  (elsewhere || drillingElsewhere)) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    context.push(
                      '/casting/point/${pt.serverId}/watch?code=${Uri.encodeComponent(pt.code)}',
                    );
                  },
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: Text(t(context).watchOpen),
                ),
              ],
            ],
          ),
        ),
              ),
            ),
          );
        },
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

  /// Toleransi simpangan titik proyek ini, dalam milimeter.
  ///
  /// `null` bila proyeknya belum tertarik — dan ketika tidak diketahui tidak
  /// ada yang dinyatakan di luar batas. Diganti nol sebagai "aman", setiap
  /// titik akan diperingatkan merah; diganti angka tetap, proyek yang
  /// toleransinya memang lain akan diperiksa dengan batas proyek lain.
  double? get toleranceMm {
    final p = (ref.read(projectsProvider).value ?? const [])
        .where((p) => '${p['id']}' == '${widget.projectId}')
        .firstOrNull;
    return toDoubleOrNull(p?['pileToleranceMm']);
  }

  /// Koordinat tersimpan sebagai teks isian; kosong bila belum ada.
  /// Nilai AWAL isian koordinat — ikut berkelompok ribuan, sama dengan
  /// yang dihasilkan `KoordinatInputFormatter` saat diketik. Dibiarkan
  /// polos, angka yang sudah tersimpan tampil berbeda dari angka yang baru
  /// diketik di isian yang sama.
  static String _koordText(double? v) => v == null ? '' : formatKoordinat(v);

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
    final result = await showDialog<({double depth, double? groundLevel, double? actualX, double? actualY})>(
      context: context,
      builder: (c) => _DrillDialog(
        code: pt.code,
        initialDepth: initialDepth == null ? '' : initialDepth.toStringAsFixed(2).replaceAll('.', ','),
        initialGs: knownGs == null ? '' : knownGs.toStringAsFixed(3).replaceAll('.', ','),
        gsRequired: knownGs == null,
        cutOffLevel: pt.cutOffLevel,
        tipLevel: pt.tipLevel,
        initialX: _koordText(pt.actualX),
        initialY: _koordText(pt.actualY),
        xyRequired: pt.actualX == null || pt.actualY == null,
        designX: pt.designX,
        designY: pt.designY,
        toleranceMm: toleranceMm,
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
        // Dikirim hanya bila ADA ISINYA. Server tidak menghapus yang kosong,
        // tetapi mengirim kunci kosong membuat jejak auditnya mencatat
        // koordinat "berubah" pada setiap tanda bor yang tidak menyentuhnya.
        if (result.actualX != null) 'actualX': decimalText(result.actualX!, decimals: 3),
        if (result.actualY != null) 'actualY': decimalText(result.actualY!, decimals: 3),
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
    required this.initialX,
    required this.initialY,
    required this.xyRequired,
    required this.designX,
    required this.designY,
    required this.toleranceMm,
  });

  final String code;
  final String initialDepth;
  final String initialGs;
  final bool gsRequired;
  final double cutOffLevel;
  final double tipLevel;
  final String initialX;
  final String initialY;
  final bool xyRequired;
  final double? designX;
  final double? designY;
  final double? toleranceMm;

  @override
  State<_DrillDialog> createState() => _DrillDialogState();
}

class _DrillDialogState extends State<_DrillDialog> {
  late final _depthInput = TextEditingController(text: widget.initialDepth);
  late final _gsInput = TextEditingController(text: widget.initialGs);
  late final _xInput = TextEditingController(text: widget.initialX);
  late final _yInput = TextEditingController(text: widget.initialY);
  String? _problem;

  double? _plannedFor(double? gs) => gs == null ? null : gs - widget.tipLevel;

  @override
  void dispose() {
    _depthInput.dispose();
    _gsInput.dispose();
    _xInput.dispose();
    _yInput.dispose();
    super.dispose();
  }


  Future<void> _submit() async {
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
    // X/Y AKTUAL diperiksa PALING AKHIR, sesudah kedalamannya.
    //
    // Diperiksa lebih dulu, yang kedalamannya salah ketik diberi tahu soal
    // koordinat — lalu memperbaiki koordinatnya dan ditolak lagi karena
    // kedalamannya, yang sejak awal yang salah.
    final salahKoord = koordinatBelumSah(
      context,
      _xInput.text,
      _yInput.text,
      wajib: widget.xyRequired,
    );
    if (salahKoord != null) {
      setState(() => _problem = salahKoord);
      return;
    }
    // PERINGATAN KERAS simpangan — sesudah seluruh pemeriksaan lain lulus.
    //
    // Ditanya lebih awal, yang kedalamannya masih salah ketik sudah
    // terlanjur menjawab pertanyaan berat soal simpangan, lalu harus
    // menjawabnya lagi sesudah membetulkan hal lain.
    if (!await lanjutkanMeskiSimpang(
      context,
      designX: widget.designX,
      designY: widget.designY,
      xText: _xInput.text,
      yText: _yInput.text,
      toleranceMm: widget.toleranceMm,
    )) {
      return;
    }
    // `mounted` MILIK STATE, bukan `context.mounted`.
    //
    // Keduanya tampak setara, tetapi penganalisis menolak yang kedua di
    // dalam `State`: yang menentukan boleh-tidaknya memakai `context`
    // sesudah `await` adalah hidup-matinya State-nya, dan `context.mounted`
    // menjawab pertanyaan yang berbeda.
    if (!mounted) return;
    Navigator.pop(context, (
      depth: depth,
      groundLevel: gs,
      actualX: parseKoordinat(_xInput.text),
      actualY: parseKoordinat(_yInput.text),
    ));
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
            // X/Y aktual: pusat lubang, diukur sesudah pengeborannya selesai
            // — jadi di sini, di dialog yang menutupnya, bukan di dialog yang
            // memulainya.
            KoordinatAktualFields(
              xInput: _xInput,
              yInput: _yInput,
              wajib: widget.xyRequired,
              designX: widget.designX,
              designY: widget.designY,
              toleranceMm: widget.toleranceMm,
              onChanged: () => setState(() => _problem = null),
            ),
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

/// Kemajuan titik yang sedang dikerjakan HP LAIN.
///
/// Angkanya "sejauh yang sudah terkirim", jadi umurnya ditampilkan sekeras
/// angkanya sendiri dan berubah kuning setelah [_basi]. Tanpa itu, kemajuan
/// yang tertinggal dua jam akan dibaca sebagai keadaan sekarang — dan
/// dipakai memutuskan pemindahan rig.
///
/// Belum ada catatan sama sekali juga sebuah jawaban ("belum ada catatan
/// terkirim"), bukan alasan menyembunyikan kartunya: layar kosong membuat
/// orang mengira fiturnya rusak.
/// HASIL pengecoran yang SUDAH SELESAI — bukan kemajuannya.
///
/// DIMINTA DANIEL, 14 Oktober 2026: *"harusnya kalau udah beres ya udah
/// kasih datanya aja bang ... sudah selesai cor, cor terakhir sampai berapa
/// meter, terus kasih ringkasan, jadinya kecor berapa m³"*.
///
/// Tidak ada bilah kemajuan dan tidak ada "terakhir sekian jam lalu" di
/// sini. Keduanya menerangkan sesuatu yang sedang berlangsung: bilah yang
/// berhenti di 97% pada tiang yang sudah jadi terbaca sebagai pekerjaan
/// yang kurang, padahal volume beton memang tidak pernah persis sama
/// dengan teoretisnya.
class _SelesaiCorCard extends StatelessWidget {
  const _SelesaiCorCard({required this.point});

  final FieldPilePoint point;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final l = t(context);
    final volume = point.castingVolumeM3 ?? 0;
    final rencana = point.plannedTheoreticalVolumeM3;
    // Selisih terhadap teoretis disebut hanya bila rencananya diketahui.
    // Dihitung dari rencana nol, angkanya tak hingga.
    final selisih = rencana < 0.01 ? null : (volume - rencana) / rencana * 100;
    final selesai = point.castingLastAt;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: w.okBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.okFg.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: w.okFg),
              const SizedBox(width: 8),
              Text(l.castDoneTitle,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: w.okFg)),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(l.castDoneVolume, '${volume.toStringAsFixed(2).replaceAll('.', ',')} m³'),
          _InfoRow(
            l.castDonePlanned,
            selisih == null
                ? '${rencana.toStringAsFixed(2).replaceAll('.', ',')} m³'
                : l.castDoneVsPlanned(
                    rencana.toStringAsFixed(2).replaceAll('.', ','),
                    '${selisih >= 0 ? '+' : ''}${selisih.toStringAsFixed(1).replaceAll('.', ',')}',
                  ),
          ),
          _InfoRow(l.castDoneTrucks, '${point.castingTruckCount ?? 0}'),
          // Muka beton TERAKHIR TERCATAT, bukan "akhir": pada log yang TM
          // terakhirnya tidak disounding, angkanya datang dari TM
          // sebelumnya — dan hanya kalimat pertama yang tetap benar.
          if (point.castingTopDepthM != null)
            _InfoRow(l.castDoneTopDepth, formatMeters(point.castingTopDepthM)),
          if (point.drillDepthM != null)
            _InfoRow(l.castDoneHoleDepth, formatMeters(point.drillDepthM)),
          if (selesai != null)
            _InfoRow(l.castDoneAt, '${longDate(selesai)} ${formatTime(selesai)}'),
        ],
      ),
    );
  }
}

class _KemajuanCard extends StatelessWidget {
  const _KemajuanCard({
    required this.label,
    required this.utama,
    required this.rasio,
    required this.kapan,
    this.berjalan = false,
  });

  final String label;
  final String? utama;
  final double? rasio;
  final DateTime? kapan;

  /// Lognya MASIH TERBUKA. Hanya dengan begitu "berhenti" berarti apa-apa:
  /// pada log yang sudah ditutup, catatan terakhir memang sudah lama dan
  /// itu bukan berhenti melainkan selesai.
  final bool berjalan;

  static const _basi = Duration(hours: 1);

  /// Tidak ada kemajuan selama ini = sedang BERHENTI.
  ///
  /// Diminta Daniel, 20 Oktober 2026: "kalau lagi berhenti atau istirahat
  /// tolong dikasih keterangan pada saat di view dari bottom sheet".
  ///
  /// Lima belas menit — ambang yang SAMA dengan `menitBerhenti` pada
  /// ringkasan kurva, supaya lembar ini dan layar Pantau tidak pernah
  /// menyatakan hal yang berbeda tentang titik yang sama.
  static const _berhenti = Duration(minutes: 15);

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final k = kapan;
    final umur = k == null ? null : DateTime.now().difference(k);
    final basi = umur != null && umur > _basi;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: w.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: w.faint)),
          const SizedBox(height: 4),
          Text(utama ?? t(context).progressNothingYet,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: utama == null ? w.muted : w.ink,
              )),
          if (rasio != null && utama != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: rasio,
                minHeight: 6,
                backgroundColor: w.line,
                color: basi ? w.warnFg : w.brand,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(basi ? Icons.history_toggle_off : Icons.schedule,
                  size: 14, color: basi ? w.warnFg : w.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  k == null
                      ? t(context).progressNoSync
                      : t(context).progressLastAt(formatTime(k), _usia(context, umur!)),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: basi ? w.warnFg : w.muted,
                    fontWeight: basi ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          // KETERANGAN BERHENTI, di bawah jam catatan terakhirnya.
          //
          // "terakhir 16:09 · 1 jam lalu" pada log yang masih terbuka dapat
          // dibaca dua cara: rig sedang berhenti, atau HP-nya yang
          // tertinggal mengirim. Keduanya menuntut tindakan yang berbeda,
          // jadi layar ini menyebutkan yang mana.
          if (berjalan && umur != null && umur > _berhenti) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.pause_circle_outline, size: 14, color: w.warnFg),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t(context).progressIdle(
                      formatTime(k!),
                      formatDuration(umur),
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: w.warnFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 2),
          Text(t(context).progressAsSent, style: TextStyle(fontSize: 11.5, color: w.faint, height: 1.35)),
        ],
      ),
    );
  }

  String _usia(BuildContext context, Duration d) {
    if (d.inMinutes < 1) return t(context).justNow;
    if (d.inHours < 1) return t(context).minutesAgo(d.inMinutes);
    if (d.inHours < 24) return t(context).hoursAgo(d.inHours);
    return t(context).daysAgo(d.inDays);
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
