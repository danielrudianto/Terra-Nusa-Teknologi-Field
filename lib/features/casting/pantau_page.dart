import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';
import '../../core/util/format.dart';
import '../../core/widgets/foto_server.dart';
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
            padding: pagePaddingAman(context),
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
      padding: pagePaddingAman(context),
      children: [
        if (cor != null)
          _PantauCor(cor: cor, kode: code)
        else if (bor != null)
          _PantauBor(bor: bor, titik: (data['titik'] as Map?)?.cast<String, Object?>())
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
  const _PantauCor({required this.cor, required this.kode});

  final Map<String, Object?> cor;

  /// Kode titiknya — ikut ke dalam teks yang dibagikan ke WhatsApp.
  final String kode;

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
              ? formatVolume(volume)
              : '${formatVolume(volume)} / ${formatVolume(teoritis)}',
        ),
        if (muka != null)
          _Angka(label: t(context).watchConcreteLevel, nilai: formatMeters(muka))
        else
          _Angka(label: t(context).watchConcreteLevel, nilai: t(context).watchNotSounded),
        if (toDoubleOrNull(k['tremieBottomM']) != null && muka != null)
          _Angka(
            label: t(context).watchEmbedment,
            nilai: formatMeters(toDoubleOrNull(k['tremieBottomM'])! - muka),
          ),

        // TABEL TM — angka di atas menjawab "sampai mana", tabel ini
        // menjawab "dari mana angka itu". Ditaruh DI BAWAH angkanya, bukan
        // di atas: yang membuka layar pantau bertanya keadaan sekarang
        // lebih dulu, dan rinciannya baru dicari sesudah angkanya terbaca
        // ganjil.
        if (tm.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TabelTm(
            tm: tm,
            kode: kode,
            sedangTuangSeq: sedangTuang ? toIntOrNull(terakhir['seq']) : null,
          ),
        ],
      ],
    );
  }
}

/// TRUK MIXER satu pengecoran — tabel yang dapat dilipat.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA ADA — Daniel, 20 Oktober 2026
/// ──────────────────────────────────────────────────────────────────────────
///
///     "sama ini juga untuk waktu pantau cor, pengen ada tabelnya gitu dong
///      bang. jadi bisa monitor juga. sekalian bisa lihat surat jalannya
///      disana"
///
/// Padanan tabel bacaan di layar pantau bor. Yang menonton pengecoran
/// sebelumnya hanya diberi JUMLAHNYA — "6 TM · 21,71 m³" — padahal yang
/// ditanyakan orang kantor selalu lebih rinci: TM keberapa yang sedang
/// dituang, berapa lama TM sebelumnya, dan apakah volumenya mulai lari dari
/// teoritis sejak TM tertentu.
///
/// KOLOM KUMULATIFNYA yang membuat tabel ini berguna, bukan daftar TM-nya:
/// penumpukan volume itulah yang dibandingkan dengan teoritis, dan selama
/// ini hanya dapat disusun orang dengan menjumlahkan sendiri di kertas.
///
/// TERTUTUP secara bawaan — sama dengan tabel bacaan bor. Layar pantau
/// dibuka untuk melihat penampang dan angka pokoknya; tabel yang terbuka
/// sendiri mendorong keduanya keluar layar.
class _TabelTm extends ConsumerStatefulWidget {
  const _TabelTm({required this.tm, required this.kode, this.sedangTuangSeq});

  final List<Map<String, Object?>> tm;
  final String kode;

  /// Nomor TM yang sedang dituang, bila ada — barisnya disorot.
  final int? sedangTuangSeq;

  @override
  ConsumerState<_TabelTm> createState() => _TabelTmState();
}

class _TabelTmState extends ConsumerState<_TabelTm> {
  bool _buka = false;

  /// Nomor TM yang sedang disiapkan untuk dibagikan.
  ///
  /// Fotonya ditarik dari server lalu diubah ke JPEG; pada jaringan lokasi
  /// itu beberapa detik, dan tombol yang diam selama itu akan ditekan lagi
  /// — menghasilkan dua lembar berbagi berturut-turut.
  int? _membagikan;

  /// BAGIKAN SATU TM — teksnya, dan surat jalannya sekalian.
  ///
  /// DIMINTA DANIEL, 20 Oktober 2026: "untuk tiap TM kasih tombol copas
  /// buat ke WhatsApp sekalian foto surat jalannya boleh?".
  ///
  /// Yang dikirim ke grup proyek selama ini disusun tangan dari layar ini:
  /// nomor TM, jam, volume, lalu fotonya dicari lagi di galeri HP yang
  /// mencatat. Disusun tangan, angkanya kadang diketik keliru — dan yang
  /// menerimanya di grup tidak punya cara memeriksanya.
  ///
  /// Fotonya TIDAK menghalangi teksnya: bila fotonya gagal ditarik (sinyal,
  /// atau sudah lewat masa simpan), teksnya tetap dibagikan dan kegagalan
  /// fotonya disebut. Teks tanpa foto masih berguna; menahan keduanya
  /// karena satu gagal tidak berguna sama sekali.
  Future<void> _bagikan(Map<String, Object?> x, double kumulatif) async {
    final seq = toIntOrNull(x['seq']) ?? 0;
    if (_membagikan != null) return;
    setState(() => _membagikan = seq);

    final l = t(context);
    final teks = StringBuffer()
      ..writeln('${widget.kode} · ${l.truckColSeq} $seq')
      ..writeln(
        '${_jamTuang(context, x)} · '
        '${formatVolume(toDoubleOrNull(x['volumeM3']) ?? 0)} '
        '(${l.truckColCumulative.toLowerCase()} ${formatVolume(kumulatif)})',
      );
    final ket = _keterangan(context, x);
    if (ket != null) teks.writeln(ket);

    XFile? foto;
    String? galatFoto;
    final uuid = x['ticketPhotoUuid']?.toString();
    if (uuid != null && uuid.isNotEmpty) {
      try {
        foto = await fotoUntukDibagikan(
          ref,
          uuid,
          'surat-jalan-${widget.kode}-TM$seq',
        );
      } catch (_) {
        galatFoto = l.shareNoPhoto;
      }
    }
    if (!mounted) return;
    setState(() => _membagikan = null);

    if (galatFoto != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(galatFoto)),
      );
    }
    await SharePlus.instance.share(
      ShareParams(
        text: teks.toString().trim(),
        files: foto == null ? null : [foto],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;

    // Kumulatif dihitung di sini, sekali, menurut urutan `seq` — bukan di
    // dalam barisnya: baris yang menjumlahkan tetangganya sendiri akan
    // salah begitu satu TM dihapus di tengah.
    var jumlah = 0.0;
    final kum = <double>[];
    for (final x in widget.tm) {
      jumlah += toDoubleOrNull(x['volumeM3']) ?? 0;
      kum.add(jumlah);
    }

    return Container(
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _buka = !_buka),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_outlined, size: 18, color: w.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context).truckTableTitle('${widget.tm.length}'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: w.ink, fontSize: 14),
                    ),
                  ),
                  Icon(_buka ? Icons.expand_less : Icons.expand_more, color: w.muted),
                ],
              ),
            ),
          ),
          if (_buka) ...[
            Divider(height: 1, color: w.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                children: [
                  _BarisTm(
                    kepala: true,
                    tm: t(context).truckColSeq,
                    jam: t(context).truckColPour,
                    volume: t(context).truckColVolume,
                    kumulatif: t(context).truckColCumulative,
                  ),
                  for (final (i, x) in widget.tm.indexed) ...[
                    Divider(height: 11, color: w.line),
                    _BarisTm(
                      tm: '${x['seq']}',
                      jam: _jamTuang(context, x),
                      volume: formatVolume(toDoubleOrNull(x['volumeM3']) ?? 0),
                      kumulatif: formatVolume(kum[i]),
                      disorot: widget.sedangTuangSeq != null &&
                          toIntOrNull(x['seq']) == widget.sedangTuangSeq,
                      ket: _keterangan(context, x),
                      catatan: x['note']?.toString(),
                      tiketUuid: x['ticketPhotoUuid']?.toString(),
                      slumpUuid: x['slumpPhotoUuid']?.toString(),
                      onBagikan: () => _bagikan(x, kum[i]),
                      sedangBagikan: _membagikan == toIntOrNull(x['seq']),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "09:12–09:31", "09:12–…" selagi dituang, "datang 09:05" sebelum mulai.
  ///
  /// TM yang sudah datang tetapi belum dituang bukan baris kosong: justru
  /// itulah yang ditanyakan ("mixernya sudah di lokasi belum"), dan jam
  /// datangnya satu-satunya jam yang dimilikinya.
  static String _jamTuang(BuildContext context, Map<String, Object?> x) {
    final mulai = DateTime.tryParse('${x['startAt']}');
    final selesai = DateTime.tryParse('${x['endAt']}');
    final datang = DateTime.tryParse('${x['arrivedAt']}');
    if (mulai == null) {
      return datang == null ? '—' : t(context).truckArrivedAt(formatTime(datang));
    }
    return selesai == null
        ? '${formatTime(mulai)}–…'
        : '${formatTime(mulai)}–${formatTime(selesai)}';
  }

  /// Baris kecil di bawahnya: pemasok, nomor lambung, nomor tiket, slump.
  ///
  /// Yang KOSONG dilewati, tidak diisi strip: empat strip berderet terbaca
  /// seperti data yang hilang, padahal nomor lambung memang sering tidak
  /// dicatat.
  static String? _keterangan(BuildContext context, Map<String, Object?> x) {
    final bagian = <String>[
      if ('${x['supplierName'] ?? ''}'.trim().isNotEmpty) '${x['supplierName']}',
      if ('${x['truckNo'] ?? ''}'.trim().isNotEmpty) t(context).hullNo('${x['truckNo']}'),
      if ('${x['ticketNo'] ?? ''}'.trim().isNotEmpty) '${x['ticketNo']}',
      if (toDoubleOrNull(x['slumpCm']) != null)
        t(context).slumpOf(
          toDoubleOrNull(x['slumpCm'])!.toStringAsFixed(1).replaceAll('.', ','),
        ),
    ];
    return bagian.isEmpty ? null : bagian.join(' · ');
  }
}

class _BarisTm extends StatelessWidget {
  const _BarisTm({
    required this.tm,
    required this.jam,
    required this.volume,
    required this.kumulatif,
    this.kepala = false,
    this.disorot = false,
    this.ket,
    this.catatan,
    this.tiketUuid,
    this.slumpUuid,
    this.onBagikan,
    this.sedangBagikan = false,
  });

  final String tm;
  final String jam;
  final String volume;
  final String kumulatif;
  final bool kepala;
  final bool disorot;
  final String? ket;
  final String? catatan;
  final String? tiketUuid;
  final String? slumpUuid;

  /// Bagikan baris ini — teks dan surat jalannya sekalian.
  final VoidCallback? onBagikan;
  final bool sedangBagikan;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final gaya = TextStyle(
      fontSize: kepala ? 11.5 : 13,
      fontWeight: kepala ? FontWeight.w700 : FontWeight.w500,
      color: kepala ? w.faint : w.ink,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: disorot ? w.brandSoft : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 30, child: Text(tm, style: gaya)),
              Expanded(child: Text(jam, style: gaya)),
              SizedBox(width: 74, child: Text(volume, style: gaya, textAlign: TextAlign.right)),
              SizedBox(width: 74, child: Text(kumulatif, style: gaya, textAlign: TextAlign.right)),
            ],
          ),
          if (ket != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(ket!, style: TextStyle(fontSize: 12, color: w.muted)),
            ),
          if (catatan != null && catatan!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(catatan!, style: TextStyle(fontSize: 12, color: w.muted)),
            ),
          // SURAT JALANNYA, dari server — satu-satunya halaman di seluruh
          // pekerjaan ini yang bertanda tangan pemasok.
          if (tiketUuid != null || slumpUuid != null || onBagikan != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  if (tiketUuid != null)
                    KepingFoto(uuid: tiketUuid!, label: t(context).deliveryNote),
                  if (tiketUuid != null && slumpUuid != null) const SizedBox(width: 6),
                  if (slumpUuid != null)
                    KepingFoto(
                      uuid: slumpUuid!,
                      label: t(context).slumpTest,
                      ikon: Icons.science_outlined,
                    ),
                  // BAGIKAN — paling kanan, terpisah dari keping foto:
                  // keping membuka foto di layar ini, tombol ini
                  // mengeluarkannya dari aplikasi. Dua perbuatan yang
                  // berbeda tidak boleh berdampingan tanpa jarak.
                  if (onBagikan != null) ...[
                    const Spacer(),
                    if (sedangBagikan)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      KepingFoto.aksi(
                        label: t(context).truckShare,
                        ikon: Icons.ios_share,
                        onKetuk: onBagikan!,
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pengeboran yang sedang berjalan: kurva kedalaman yang tumbuh tiap bacaan.
class _PantauBor extends StatefulWidget {
  const _PantauBor({required this.bor, this.titik});

  final Map<String, Object?> bor;

  /// Titiknya, untuk panjang bor RENCANA pada penampangnya. Boleh `null`:
  /// penampangnya lalu digambar tanpa garis sasaran, bukan dengan sasaran
  /// tebakan.
  final Map<String, Object?>? titik;

  @override
  State<_PantauBor> createState() => _PantauBorState();
}

class _PantauBorState extends State<_PantauBor> {
  /// `waktu` bacaan yang sedang disorot — satu nilai untuk DUA tampilan.
  ///
  /// DIMINTA DANIEL, 20 Oktober 2026: "kalau diklik titiknya, di tabelnya
  /// di-highlight".
  ///
  /// Disimpan di INDUK, bukan di kurva atau di tabel: begitu masing-masing
  /// menyimpan pilihannya sendiri, keduanya dapat menyorot bacaan yang
  /// berbeda pada saat yang sama — dan layar yang menyorot dua hal sekaligus
  /// tidak menjawab apa pun.
  int? _pilih;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final bor = widget.bor;
    final titik = widget.titik;
    final bacaan = [
      for (final e in (bor['entries'] as List?) ?? const []) (e as Map).cast<String, Object?>(),
    ];
    // Dinamai `bacaanTitik`, bukan `titik`: bidang `titik` pada widget ini
    // adalah TITIK BORNYA, dan dua hal berbeda bernama sama di satu
    // metode adalah cara tercepat menukar keduanya tanpa sadar.
    final bacaanTitik = titikKurvaBor(bacaan);
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
        // KURVA SAJA — penampang beranimasinya DIBATALKAN.
        //
        // Dicoba 19 Oktober 2026, lalu dicabut hari itu juga atas
        // permintaan Daniel: "setelah dicobain mah gajadi deh bang, jelek
        // banget pakai icon animasi animasi gitu, ga cocok". Dicatat di
        // sini supaya tidak ada yang mengusulkannya lagi sebagai ide baru.
        //
        // YANG DIPERTAHANKAN dari percobaan itu dua, dan keduanya soal
        // angka, bukan hiasan: sumbu kedalaman turun sampai RENCANA + 5 m,
        // dan garis acuan tip rencana di kurvanya.
        if (bacaanTitik.length >= 2)
          KurvaBor(
            titik: bacaanTitik,
            ringkas: ringkas,
            rencanaM: toDoubleOrNull(titik?['panjangBorRencanaM']),
            skalaDalamM: skalaKedalaman(
              rencanaM: toDoubleOrNull(titik?['panjangBorRencanaM']),
              kedalamanM: ringkas.kedalamanM ?? 0,
            ),
            waktuDipilih: _pilih,
            // Ketukan KEDUA pada bacaan yang sama melepas sorotannya.
            onKetuk: (waktu) =>
                setState(() => _pilih = _pilih == waktu ? null : waktu),
          )
        else
          TerraBanner(
            kind: BannerKind.info,
            icon: Icons.show_chart,
            title: t(context).watchCurveWaitTitle,
            body: t(context).watchCurveWaitBody,
          ),
        const SizedBox(height: 14),
        _Angka(label: t(context).watchDepth, nilai: formatMeters(ringkas.kedalamanM)),
        if (ringkas.lajuRataMPerJam != null)
          _Angka(
            label: t(context).watchRate,
            nilai: '${formatMeters(ringkas.lajuRataMPerJam)}/jam',
          ),
        _Angka(label: t(context).watchReadings, nilai: '${ringkas.jumlahBacaan}'),
        if (bacaan.isNotEmpty) ...[
          const SizedBox(height: 8),
          _TabelBacaan(
            bacaan: bacaan,
            dipilih: _pilih,
            onPilih: (waktu) =>
                setState(() => _pilih = _pilih == waktu ? null : waktu),
          ),
        ],
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

/// DAFTAR BACAAN yang dapat dibuka-tutup.
///
/// DIMINTA DANIEL, 20 Oktober 2026: "waktu pantau pengeboran dikasih table
/// deh inputnya apa saja, expandable".
///
/// Kurva menjawab "bagaimana bentuknya", tabel menjawab "apa persisnya yang
/// diketik orang di sana" — dan pertanyaan kedua itulah yang muncul begitu
/// ada angka yang terlihat ganjil pada kurvanya.
///
/// TERTUTUP secara bawaan: layar ini dibuka untuk melihat keadaan sekarang,
/// bukan untuk membaca tujuh baris angka. Yang memerlukannya membukanya
/// sekali.
///
/// BACAAN YANG TIDAK TERGAMBAR IKUT DIDAFTAR, ditandai. Lihat
/// [barisBacaan]: bacaan yang jam atau kedalamannya tidak terbaca dibuang
/// dari kurvanya — benar untuk kurvanya — tetapi dibuang juga dari sini, ia
/// tidak muncul di layar mana pun dan tidak akan pernah dibetulkan siapa
/// pun, sementara kedalaman akhir titik itu diam-diam tetap salah.
class _TabelBacaan extends StatefulWidget {
  const _TabelBacaan({
    required this.bacaan,
    this.dipilih,
    this.onPilih,
  });

  final List<Map<String, Object?>> bacaan;

  /// `waktu` bacaan yang sedang disorot — nilainya milik induk, dipakai
  /// bersama kurvanya.
  final int? dipilih;

  final void Function(int waktu)? onPilih;

  @override
  State<_TabelBacaan> createState() => _TabelBacaanState();
}

class _TabelBacaanState extends State<_TabelBacaan> {
  bool _buka = false;

  /// MEMBUKA SENDIRI saat ada bacaan yang disorot dari kurvanya.
  ///
  /// Menyorot baris di dalam tabel yang tertutup sama saja dengan tidak
  /// menyorot apa pun: yang mengetuk kurva tidak diberi tahu bahwa
  /// jawabannya ada di balik tajuk yang masih terlipat.
  @override
  void didUpdateWidget(_TabelBacaan old) {
    super.didUpdateWidget(old);
    if (widget.dipilih != null && widget.dipilih != old.dipilih && !_buka) {
      setState(() => _buka = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final baris = barisBacaan(widget.bacaan);

    return Container(
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: w.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _buka = !_buka),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Icon(Icons.list_alt, size: 18, color: w.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(context).readingTableTitle('${baris.length}'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: w.ink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(_buka ? Icons.expand_less : Icons.expand_more,
                      color: w.muted),
                ],
              ),
            ),
          ),
          if (_buka) ...[
            Divider(height: 1, color: w.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(
                children: [
                  _BarisTabel(
                    jam: t(context).readingColTime,
                    dalam: t(context).readingColDepth,
                    tambah: t(context).readingColAdded,
                    laju: t(context).readingColRate,
                    kepala: true,
                  ),
                  for (final b in baris) ...[
                    Divider(height: 11, color: w.line),
                    _BarisTabel(
                      disorot: b.waktu != null && b.waktu == widget.dipilih,
                      onKetuk: b.waktu == null || widget.onPilih == null
                          ? null
                          : () => widget.onPilih!(b.waktu!),
                      jam: b.waktu == null
                          ? '—'
                          : formatTime(
                              DateTime.fromMillisecondsSinceEpoch(b.waktu!)),
                      dalam: formatMeters(b.dalam),
                      tambah: b.deltaM == null
                          ? '—'
                          : '${b.deltaM! >= 0 ? '+' : ''}${formatMeters(b.deltaM)}',
                      laju: b.lajuMPerJam == null
                          ? '—'
                          : t(context).metresPerHour(b.lajuMPerJam!
                              .toStringAsFixed(1)
                              .replaceAll('.', ',')),
                      // Ruas MUNDUR disorot: bor yang diangkat lalu dibaca
                      // lagi sah, tetapi salah ketik juga menghasilkan
                      // bentuk yang sama — dan hanya yang ada di lokasi
                      // dapat membedakannya.
                      sorot: (b.deltaM ?? 0) < 0,
                      catatan: b.bacaan['note']?.toString(),
                      takTergambar: !b.tergambar,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarisTabel extends StatelessWidget {
  const _BarisTabel({
    required this.jam,
    required this.dalam,
    required this.tambah,
    required this.laju,
    this.kepala = false,
    this.sorot = false,
    this.catatan,
    this.takTergambar = false,
    this.disorot = false,
    this.onKetuk,
  });

  final String jam;
  final String dalam;
  final String tambah;
  final String laju;
  final bool kepala;
  final bool sorot;
  final String? catatan;
  final bool takTergambar;

  /// Bacaan ini yang sedang dipilih di kurvanya.
  final bool disorot;

  final VoidCallback? onKetuk;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final gaya = TextStyle(
      fontSize: kepala ? 11.5 : 13,
      fontWeight: kepala ? FontWeight.w700 : FontWeight.w500,
      color: kepala
          ? w.faint
          : sorot
              ? w.warnFg
              : w.ink,
    );
    final isi = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(width: 54, child: Text(jam, style: gaya)),
            Expanded(child: Text(dalam, style: gaya, textAlign: TextAlign.right)),
            SizedBox(
              width: 78,
              child: Text(tambah, style: gaya, textAlign: TextAlign.right),
            ),
            SizedBox(
              width: 86,
              child: Text(laju, style: gaya, textAlign: TextAlign.right),
            ),
          ],
        ),
        if (catatan != null && catatan!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(catatan!,
                style: TextStyle(fontSize: 12, color: w.muted)),
          ),
        if (takTergambar)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(t(context).readingNotPlotted,
                style: TextStyle(fontSize: 12, color: w.badFg)),
          ),
      ],
    );

    // Barisnya DAPAT DIKETUK juga — menyorot dua arah. Yang membaca tabel
    // lalu bertanya "yang ini di sebelah mana kurvanya" mendapat jawabannya
    // dengan gerakan yang sama.
    return InkWell(
      onTap: onKetuk,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: disorot ? w.brandSoft : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isi,
      ),
    );
  }
}
