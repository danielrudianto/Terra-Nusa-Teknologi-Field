import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/util/format.dart';
import '../../core/widgets/list_card.dart';

/// Satu baris kegiatan lapangan dalam 24 jam terakhir.
class Kegiatan {
  const Kegiatan({
    required this.bor,
    required this.kode,
    required this.pilePointID,
    required this.kapan,
    required this.selesai,
    required this.utama,
    required this.ket,
  });

  /// Pengeboran (true) atau pengecoran (false).
  final bool bor;
  final String kode;

  /// `null` bila servernya belum ter-deploy: barisnya tetap tampil, hanya
  /// tidak dapat diketuk. Lebih baik daripada ketukan yang tidak membuka
  /// apa pun.
  final int? pilePointID;

  /// Jam yang dipakai mengurutkan DAN yang ditampilkan.
  final DateTime kapan;

  /// Pekerjaannya sudah ditutup. Yang belum, jamnya adalah kabar terakhir.
  final bool selesai;

  /// Angka hasilnya: "28,90 m" atau "6 TM · 21,71 m³".
  final String utama;

  /// Baris kecil di bawahnya — nama pencatat, proyek.
  final String ket;
}

/// Sama hari kalender dengan [acuan]?
///
/// HARI INI, bukan 24 jam bergulir (diubah Daniel, 19 Okt 2026). Bedanya
/// terasa pagi hari: jendela bergulir masih memuat pekerjaan kemarin sore,
/// dan "hari ini" yang memuat kemarin membuat orang salah hitung.
bool _hariYangSama(DateTime a, DateTime acuan) =>
    a.year == acuan.year && a.month == acuan.month && a.day == acuan.day;

double? _d(Object? v) => toDoubleOrNull(v);

DateTime? _jam(Object? v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

/// Susun daftar kegiatan dari jawaban `/field/reports`.
///
/// DIPISAH dari pengambilannya supaya dapat diuji tanpa jaringan — dan
/// karena penyaringan 24 jam inilah bagian yang paling mudah salah.
List<Kegiatan> susunKegiatan(Map<String, Object?> jawaban, DateTime sekarang) {
  final hasil = <Kegiatan>[];

  for (final x in (jawaban['drilling'] as List? ?? const [])) {
    final m = (x as Map).cast<String, Object?>();
    // `endAt` = bacaan terakhir, atau jam titik ditandai dibor langsung.
    // Tanpa jam sama sekali, barisnya DILEWATI: kegiatan tanpa jam tidak
    // dapat diurutkan maupun dinyatakan "dalam 24 jam terakhir", dan
    // menaruhnya di pucuk daftar akan menyesatkan.
    final kapan = _jam(m['endAt']) ?? _jam(m['startAt']);
    if (kapan == null || !_hariYangSama(kapan, sekarang)) continue;
    final dalam = _d(m['depthM']);
    hasil.add(Kegiatan(
      bor: true,
      kode: '${m['pilePointCode']}',
      pilePointID: toIntOrNull(m['pilePointID']),
      kapan: kapan,
      selesai: '${m['status']}' != 'berjalan',
      // `formatMeters` SUDAH menempelkan satuannya, berikut spasi tak
      // terputus. Ditambah ' m' lagi, hasilnya "14,00 m m" — dilaporkan
      // Daniel 19 Okt 2026.
      utama: dalam == null ? '—' : formatMeters(dalam),
      ket: '${m['operatorName'] ?? m['byName'] ?? ''}',
    ));
  }

  for (final x in (jawaban['casting'] as List? ?? const [])) {
    final m = (x as Map).cast<String, Object?>();
    final kapan = _jam(m['endAt']) ?? _jam(m['startAt']);
    if (kapan == null || !_hariYangSama(kapan, sekarang)) continue;
    final tm = toIntOrNull(m['trucks']) ?? 0;
    final vol = _d(m['volumeM3']) ?? 0;
    hasil.add(Kegiatan(
      bor: false,
      kode: '${m['pilePointCode']}',
      pilePointID: toIntOrNull(m['pilePointID']),
      kapan: kapan,
      selesai: '${m['status']}' != 'berjalan',
      utama: '$tm TM · ${formatVolume(vol)}',
      ket: '${m['byName'] ?? ''}',
    ));
  }

  // Terbaru di atas: yang baru saja selesai itulah yang dicari orang saat
  // membuka aplikasi.
  hasil.sort((a, b) => b.kapan.compareTo(a.kapan));
  return hasil;
}

/// Kegiatan lapangan HARI INI, dari server.
final aktivitasHariIniProvider =
    FutureProvider.autoDispose<List<Kegiatan>>((ref) async {
  final kini = DateTime.now();
  final jawaban = await ref.read(apiProvider).report(kini, kini);
  return susunKegiatan(jawaban, kini);
});

/// "Sejauh mana pekerjaan hari ini" — di beranda.
///
/// ──────────────────────────────────────────────────────────────────────────
/// KENAPA ADA — Daniel, 19 Oktober 2026
/// ──────────────────────────────────────────────────────────────────────────
///
///     "Do home page dikasih tau titik ini udah bor sampai mana. Cor udah
///      sampai mana, jam berapa cor mana baru beres. The last 24 hours aja"
///
/// Sebelum ini, menjawabnya menuntut membuka halaman Laporan, memilih
/// tanggal, lalu membaca dua tabel.
///
/// DIAM TOTAL bila tidak ada kegiatan, dan bila penggunanya tidak berhak
/// membaca laporan lapangan. Gagal memuat juga diam: beranda bukan tempat
/// melaporkan kegagalan sesuatu yang tidak diminta siapa pun.
class AktivitasHariIniCard extends ConsumerStatefulWidget {
  const AktivitasHariIniCard({super.key});

  /// Paling banyak baris yang ditampilkan saat terbuka.
  ///
  /// Hari sibuk dapat menghasilkan tiga puluh baris, dan beranda bukan
  /// halaman laporan. Yang terpotong disebutkan jumlahnya, bukan
  /// dihilangkan diam-diam.
  static const maksBaris = 6;

  /// Kunci penyimpanan pilihan buka/tutup.
  static const kunciTerbuka = 'aktivitas_hari_ini_terbuka';

  @override
  ConsumerState<AktivitasHariIniCard> createState() => _AktivitasHariIniCardState();
}

class _AktivitasHariIniCardState extends ConsumerState<AktivitasHariIniCard>
    with WidgetsBindingObserver {
  /// SEBERAPA SERING ISINYA DIPERBARUI SENDIRI.
  ///
  /// KENAPA ADA — Daniel, 19 Oktober 2026, dengan dua tangkapan layar:
  /// kartu ini menulis "SP.B46 masih jalan · terakhir 11:55 · 20,50 m",
  /// sementara layar Pantau titik yang sama menulis "Bor selesai per
  /// 13:52 · 29,20 m".
  ///
  /// Keduanya benar pada saat masing-masing dibaca. Beranda duduk di
  /// `StatefulShellBranch` yang TIDAK PERNAH dibongkar, jadi penyedianya —
  /// meski `autoDispose` — tetap ditonton sepanjang hari dan jawabannya
  /// membeku pada jam pertama aplikasi dibuka. Pagi hari kartunya benar;
  /// sore hari ia memberitahukan keadaan empat jam yang lalu, tanpa satu
  /// pun tanda bahwa angkanya sudah tua.
  ///
  /// Kartu yang berbohong lebih buruk daripada kartu yang tidak ada:
  /// seluruh gunanya adalah menjawab "sampai mana hari ini" tanpa membuka
  /// apa pun, dan jawaban basi membuat orang membuka Pantau untuk
  /// memeriksanya — yaitu persis pekerjaan yang hendak dihilangkannya.
  ///
  /// Dua menit, bukan sepuluh detik: ini ringkasan sehari, bukan layar
  /// pemantauan, dan satu permintaan tiap dua menit tidak terasa pada
  /// kuota maupun baterai.
  static const _selang = Duration(minutes: 2);

  Timer? _jam;

  /// TERBUKA secara bawaan.
  ///
  /// Kartu yang tertutup pada pemasangan pertama tidak akan pernah dibuka
  /// oleh yang tidak tahu isinya. Yang merasa terganggu tinggal menutupnya
  /// sekali, dan pilihannya diingat.
  bool _terbuka = true;

  @override
  void initState() {
    super.initState();
    _muatPilihan();
    WidgetsBinding.instance.addObserver(this);
    _jam = Timer.periodic(_selang, (_) => _segarkan());
  }

  @override
  void dispose() {
    _jam?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Kembali dari latar belakang: SEGARKAN SEKARANG, jangan tunggu
  /// pencacah berikutnya.
  ///
  /// HP di saku sepanjang pengecoran tidak menjalankan pencacah mana pun.
  /// Yang membuka aplikasi sesudahnya melihat kartu lama persis pada saat
  /// ia paling ingin tahu — dan menunggu dua menit sambil menatap angka
  /// yang salah adalah dua menit yang membuat kartunya tidak dipercaya
  /// lagi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState keadaan) {
    if (keadaan == AppLifecycleState.resumed) _segarkan();
  }

  void _segarkan() {
    if (!mounted) return;
    ref.invalidate(aktivitasHariIniProvider);
  }

  Future<void> _muatPilihan() async {
    final v = await ref.read(dbProvider).readMeta(AktivitasHariIniCard.kunciTerbuka);
    if (!mounted || v == null) return;
    setState(() => _terbuka = v == '1');
  }

  Future<void> _ganti() async {
    final baru = !_terbuka;
    setState(() => _terbuka = baru);
    await ref.read(dbProvider).writeMeta(
          AktivitasHariIniCard.kunciTerbuka,
          baru ? '1' : '0',
        );
  }

  /// Masih jalan → PANTAU. Sudah beres → RIWAYAT.
  ///
  /// Diminta Daniel, 19 Okt 2026. Dua layar untuk dua pertanyaan yang
  /// berbeda: yang berjalan ditanya "sampai mana sekarang", yang sudah
  /// beres ditanya "tadi bagaimana". Membuka Pantau pada titik yang sudah
  /// selesai hanya menampilkan keadaan akhir yang tidak akan berubah —
  /// layar yang menjanjikan gerak lalu diam terbaca sebagai rusak.
  void _buka(Kegiatan k) {
    final id = k.pilePointID;
    if (id == null) return;
    final rute = k.selesai ? 'history' : 'watch';
    context.push('/casting/point/$id/$rute?code=${Uri.encodeComponent(k.kode)}');
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final data = ref.watch(aktivitasHariIniProvider).value;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    final tampil = data.take(AktivitasHariIniCard.maksBaris).toList();
    final sisa = data.length - tampil.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ListCard(
        onTap: _ganti,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.today, size: 18, color: w.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t(context).activityTodayTitle,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                // BADGE: jumlahnya terbaca walau kartunya tertutup — itu
                // seluruh gunanya bisa ditutup tanpa kehilangan kabar.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: w.brandSoft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${data.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: w.brandStrong,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _terbuka ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: w.muted,
                ),
              ],
            ),
            if (_terbuka) ...[
              const SizedBox(height: 10),
              for (final k in tampil) ...[
                _Baris(k: k, onKetuk: () => _buka(k)),
                if (k != tampil.last) const Divider(height: 14),
              ],
              if (sisa > 0) ...[
                const SizedBox(height: 8),
                Text(
                  t(context).activityTodayMore(sisa),
                  style: TextStyle(fontSize: 12, color: w.faint),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Baris extends StatelessWidget {
  const _Baris({required this.k, required this.onKetuk});

  final Kegiatan k;
  final VoidCallback onKetuk;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    // Ketukan baris TIDAK boleh ikut melipat kartunya: `ListCard.onTap`
    // membungkus seluruh isi, jadi barisnya memasang penadah sendiri.
    return InkWell(
      onTap: k.pilePointID == null ? null : onKetuk,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _isi(context, w),
      ),
    );
  }

  Widget _isi(BuildContext context, TerraColors w) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          k.bor ? Icons.construction : Icons.local_shipping,
          size: 18,
          color: k.bor ? w.warnFg : w.brand,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k.kode, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 1),
              Text(
                // Jamnya SELALU disebut, dan statusnya ikut: "beres 10:45"
                // menjawab pertanyaannya, "terakhir 10:45" menyatakan bahwa
                // pekerjaannya masih jalan dan angkanya belum akhir.
                k.selesai
                    ? t(context).activityTodayDone(formatTime(k.kapan))
                    : t(context).activityTodayRunning(formatTime(k.kapan)),
                style: TextStyle(fontSize: 12, color: k.selesai ? w.muted : w.warnFg),
              ),
              if (k.ket.trim().isNotEmpty)
                Text(k.ket, style: TextStyle(fontSize: 11.5, color: w.faint)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          k.utama,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
