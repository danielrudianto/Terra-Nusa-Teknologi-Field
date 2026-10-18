import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/terra_banner.dart';
import '../../core/i18n.dart';
import '../drilling/bor_kurva.dart';
import '../drilling/bor_kurva_view.dart';
import 'calc/pile_snapshot.dart';
import 'pile_section_view.dart';

/// PANTAU satu titik yang sedang dikerjakan HP lain.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA LAYAR INI ADA — Daniel, 18 Okt 2026
/// ──────────────────────────────────────────────────────────────────────────
///
///     "Gw pengen ada live view baik di bor atau dicor, kasih tau progress
///      Nya sampai mana. Kaya lagi nonton animssi aja bang"
///
/// Penampangnya sendiri sudah ada sejak lama (`PileSectionView`) — beton
/// naik, tremie menggantung, garis mengalir selama menuang. Tetapi ia
/// digambar dari dokumen log di HP yang MEMEGANGNYA, jadi selama ini hanya
/// satu orang yang pernah melihatnya. Penonton tidak punya dokumen itu.
///
/// Maka layar ini menggambar penampang yang sama dari angka SERVER
/// (`riwayat.keadaanSekarang`), bukan dari dokumen lokal.
///
/// ──────────────────────────────────────────────────────────────────────────
/// INI TIDAK DETIK-PER-DETIK, DAN LAYARNYA MENGAKUINYA
/// ──────────────────────────────────────────────────────────────────────────
///
/// Angkanya baru pindah saat HP pemegangnya sinkron. Kalau QS di lubang
/// tanpa sinyal 20 menit, layar ini diam 20 menit — bukan karena rusak.
///
/// Karena itu JAM DATANYA selalu disebut, dan umurnya dihitung di layar:
/// "per 09:48 · 3 menit lalu". Begitu angkanya menua, yang menonton tahu
/// sebabnya sinyal, bukan pekerjaan yang berhenti. Tanpa itu layar ini akan
/// mengulang penyakit kartu lama — diam, dan membuat orang menebak.
class PantauPage extends ConsumerStatefulWidget {
  const PantauPage({super.key, required this.pileId, required this.code});

  final int pileId;
  final String code;

  @override
  ConsumerState<PantauPage> createState() => _PantauPageState();
}

/// Setiap berapa lama data ditarik ulang selagi layar ini terbuka.
///
/// 20 detik: cukup rapat untuk terasa hidup, cukup jarang untuk tidak
/// menghabiskan kuota kru yang menontonnya dari lokasi. Penarikannya
/// BERHENTI saat layar tidak terlihat — lihat `didChangeAppLifecycleState`.
const _selang = Duration(seconds: 20);

class _PantauPageState extends ConsumerState<PantauPage> with WidgetsBindingObserver {
  Timer? _jam;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mulai();
  }

  @override
  void dispose() {
    _jam?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Berhenti menarik saat aplikasi tidak di depan.
  ///
  /// Penarikan yang jalan terus di layar yang tidak dilihat siapa pun
  /// menghabiskan baterai dan kuota orang yang sedang bekerja — dan di
  /// lapangan dua-duanya barang langka.
  @override
  void didChangeAppLifecycleState(AppLifecycleState keadaan) {
    if (keadaan == AppLifecycleState.resumed) {
      _mulai();
      _tarik();
    } else {
      _jam?.cancel();
      _jam = null;
    }
  }

  void _mulai() {
    _jam?.cancel();
    _jam = Timer.periodic(_selang, (_) => _tarik());
  }

  void _tarik() {
    if (!mounted) return;
    ref.invalidate(pantauProvider(widget.pileId));
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(pantauProvider(widget.pileId));
    return Scaffold(
      appBar: AppBar(title: Text(t(context).watchTitle(widget.code))),
      body: RefreshIndicator(
        onRefresh: () async => _tarik(),
        child: data.when(
          loading: () => const SkeletonCards(leading: false),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(Dimens.pagePadding),
            children: [
              TerraBanner(
                kind: BannerKind.danger,
                icon: Icons.cloud_off,
                title: t(context).watchOfflineTitle,
                body: t(context).watchOfflineBody,
              ),
            ],
          ),
          data: (d) => _Isi(data: d, code: widget.code),
        ),
      ),
    );
  }
}

/// Riwayat titik, ditarik ulang berkala oleh [PantauPage].
///
/// Sengaja TERPISAH dari provider layar riwayat: layar riwayat dibaca sekali
/// dan ditinggalkan, layar ini menarik tiap 20 detik. Dijadikan satu, membuka
/// riwayat akan ikut menyalakan penarikan berkala — dan mematikan penarikan
/// di sini akan ikut mengosongkan riwayat.
final pantauProvider = FutureProvider.autoDispose.family<Map<String, Object?>, int>(
  (ref, pileId) => ref.read(apiProvider).pointHistory(pileId),
);

class _Isi extends StatelessWidget {
  const _Isi({required this.data, required this.code});

  final Map<String, Object?> data;
  final String code;

  /// Log cor HIDUP yang paling akhir pada titik ini.
  Map<String, Object?>? get _cor {
    final semua = ((data['castings'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .where((c) => c['isDelete'] != true && c['isDelete'] != 1)
        .toList();
    return semua.isEmpty ? null : semua.last;
  }

  Map<String, Object?>? get _bor {
    final semua = ((data['drillLogs'] as List?) ?? const [])
        .map((x) => (x as Map).cast<String, Object?>())
        .where((l) => l['isDelete'] != true && l['isDelete'] != 1)
        .toList();
    return semua.isEmpty ? null : semua.last;
  }

  @override
  Widget build(BuildContext context) {
    final cor = _cor;
    final bor = _bor;

    return ListView(
      padding: const EdgeInsets.all(Dimens.pagePadding),
      children: [
        if (cor != null)
          _PantauCor(cor: cor)
        else if (bor != null)
          _PantauBor(bor: bor)
        else
          TerraBanner(
            kind: BannerKind.info,
            icon: Icons.hourglass_empty,
            title: t(context).watchNothingTitle,
            body: t(context).watchNothingBody,
          ),
      ],
    );
  }
}

/// Umur data: "per 09:48 · 3 menit lalu".
///
/// Satu-satunya hal yang membuat layar yang diam dapat dipercaya.
class _Umur extends StatelessWidget {
  const _Umur({required this.pada});

  final DateTime? pada;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    if (pada == null) {
      return Text(t(context).watchNoTimestamp, style: TextStyle(fontSize: 12, color: w.muted));
    }
    final menit = DateTime.now().difference(pada!).inMinutes;
    // Lewat 15 menit: ditonjolkan. Bukan galat — tetapi yang menonton perlu
    // berhenti menganggap angka di layar ini sebagai keadaan sekarang.
    final tua = menit >= 15;
    return Row(
      children: [
        Icon(tua ? Icons.history_toggle_off : Icons.schedule, size: 14, color: tua ? w.warnFg : w.muted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            t(context).watchAsOf(formatTime(pada!), menit),
            style: TextStyle(fontSize: 12, color: tua ? w.warnFg : w.muted, fontWeight: tua ? FontWeight.w700 : null),
          ),
        ),
      ],
    );
  }
}

/// Pengecoran yang sedang berjalan: penampang lubang + angka pokoknya.
class _PantauCor extends StatelessWidget {
  const _PantauCor({required this.cor});

  final Map<String, Object?> cor;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final h = ((cor['hitungan'] as Map?) ?? const {}).cast<String, Object?>();
    final k = ((h['keadaanSekarang'] as Map?) ?? const {}).cast<String, Object?>();
    final tm = ((cor['trucks'] as List?) ?? const []).map((x) => (x as Map).cast<String, Object?>()).toList()
      ..sort((a, b) => (toIntOrNull(a['seq']) ?? 0).compareTo(toIntOrNull(b['seq']) ?? 0));

    final dasar = toDoubleOrNull(k['dasarLubangM']);
    final selesai = '${cor['status']}' == 'selesai';

    // TM terakhir yang SUDAH mulai tetapi BELUM selesai = sedang dituang.
    final terakhir = tm.isEmpty ? null : tm.last;
    final sedangTuang = !selesai &&
        terakhir != null &&
        terakhir['startAt'] != null &&
        terakhir['endAt'] == null;

    // Jam data: yang terakhir benar-benar tercatat pada TM mana pun.
    final jam = [
      for (final x in tm) ...[
        DateTime.tryParse('${x['endAt']}'),
        DateTime.tryParse('${x['startAt']}'),
        DateTime.tryParse('${x['arrivedAt']}'),
      ],
    ].whereType<DateTime>().toList()
      ..sort();

    final muka = toDoubleOrNull(k['mukaSekarangM']);
    final volume = toDoubleOrNull(h['volumeAktualM3']) ?? 0;
    final teoritis = toDoubleOrNull(h['volumeTeoritisAktualM3']) ?? toDoubleOrNull(h['volumeTeoritisRencanaM3']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                selesai ? t(context).watchCastDone : t(context).watchCastRunning,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: w.ink),
              ),
            ),
            if (sedangTuang)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: w.brandSoft, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  t(context).watchPouringNow('${terakhir['seq']}'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: w.brand),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _Umur(pada: jam.isEmpty ? null : jam.last),
        const SizedBox(height: 14),

        // Penampangnya hanya dapat digambar kalau dasar lubangnya diketahui.
        // Tanpa itu tidak ada skala kedalaman sama sekali, dan gambar tanpa
        // skala lebih menyesatkan daripada tidak ada gambar.
        if (dasar != null && dasar > 0)
          PileSectionView(
            snapshot: PileSnapshot(
              bottomDepthM: dasar,
              cutOffDepthM: toDoubleOrNull(k['cutOffM']) ?? 0,
              // Belum pernah disounding = beton masih di dasar, DAN
              // `concreteMeasured: false` supaya penampangnya sendiri yang
              // menyatakan angka itu belum diukur siapa pun.
              concreteNowM: muka ?? dasar,
              concreteMeasured: muka != null,
              // Penonton TIDAK menaksir sasaran TM yang sedang dituang.
              // Taksiran itu hidup di HP pemegangnya, dari volume yang ia
              // ketik sendiri; digambar di sini ia akan terbaca sebagai
              // hasil ukur.
              concreteTargetM: null,
              tremieBottomM: toDoubleOrNull(k['tremieBottomM']) ?? dasar,
              tremieSegmentsM: [
                for (final s in ((k['segmenTerpasangM'] as List?) ?? const []))
                  toDoubleOrNull(s) ?? 0,
              ],
              hasBottomPiece: k['adaUjungBawah'] == true,
            ),
            pouring: sedangTuang,
            paused: false,
          ),

        const SizedBox(height: 14),
        _Angka(label: t(context).watchTrucks, nilai: '${tm.length}'),
        _Angka(
          label: t(context).watchVolume,
          nilai: teoritis == null
              ? '${formatMeters(volume)} m³'
              : '${formatMeters(volume)} / ${formatMeters(teoritis)} m³',
        ),
        if (muka != null)
          _Angka(label: t(context).watchConcreteLevel, nilai: '${formatMeters(muka)} m')
        else
          _Angka(label: t(context).watchConcreteLevel, nilai: t(context).watchNotSounded),
        if (toDoubleOrNull(k['tremieBottomM']) != null && muka != null)
          _Angka(
            label: t(context).watchEmbedment,
            nilai: '${formatMeters(toDoubleOrNull(k['tremieBottomM'])! - muka)} m',
          ),
      ],
    );
  }
}

/// Pengeboran yang sedang berjalan: kurva kedalaman yang tumbuh tiap bacaan.
class _PantauBor extends StatelessWidget {
  const _PantauBor({required this.bor});

  final Map<String, Object?> bor;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final bacaan = [
      for (final e in (bor['entries'] as List?) ?? const []) (e as Map).cast<String, Object?>(),
    ];
    final titik = titikKurvaBor(bacaan);
    final ringkas = ringkasBor(bacaan);
    final selesai = '${bor['status']}' == 'selesai';
    final jam = [
      for (final e in bacaan) DateTime.tryParse('${e['at']}'),
    ].whereType<DateTime>().toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selesai ? t(context).watchDrillDone : t(context).watchDrillRunning,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: w.ink),
        ),
        const SizedBox(height: 4),
        _Umur(pada: jam.isEmpty ? null : jam.last),
        const SizedBox(height: 14),
        if (titik.length >= 2)
          KurvaBor(titik: titik, ringkas: ringkas)
        else
          TerraBanner(
            kind: BannerKind.info,
            icon: Icons.show_chart,
            title: t(context).watchCurveWaitTitle,
            body: t(context).watchCurveWaitBody,
          ),
        const SizedBox(height: 14),
        _Angka(label: t(context).watchDepth, nilai: '${formatMeters(ringkas.kedalamanM)} m'),
        if (ringkas.lajuRataMPerJam != null)
          _Angka(
            label: t(context).watchRate,
            nilai: '${formatMeters(ringkas.lajuRataMPerJam)} m/jam',
          ),
        _Angka(label: t(context).watchReadings, nilai: '${ringkas.jumlahBacaan}'),
      ],
    );
  }
}

/// Satu baris angka: label di kiri, nilainya di kanan.
class _Angka extends StatelessWidget {
  const _Angka({required this.label, required this.nilai});

  final String label;
  final String nilai;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: w.muted))),
          Text(nilai, style: TextStyle(fontWeight: FontWeight.w800, color: w.ink, fontSize: 16)),
        ],
      ),
    );
  }
}
