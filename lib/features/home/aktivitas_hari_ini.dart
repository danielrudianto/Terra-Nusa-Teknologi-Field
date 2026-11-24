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
    required this.projectID,
    required this.kapan,
    required this.selesai,
    required this.utama,
    required this.ket,
    this.preparing = false,
    this.depthM,
    this.metersM,
    this.volumeM3,
    this.trucks = 0,
  });

  /// Pengeboran (true) atau pengecoran (false).
  final bool bor;
  final String kode;

  /// `null` bila servernya belum ter-deploy: barisnya tetap tampil, hanya
  /// tidak dapat diketuk. Lebih baik daripada ketukan yang tidak membuka
  /// apa pun.
  final int? pilePointID;

  /// Proyek pemilik titik ini — dipakai HALAMAN AKTIVITAS untuk
  /// mengelompokkan barisnya (diminta Daniel, 20 Okt 2026: "kayanya gw
  /// minta dibagi per proyek deh, siapa tau suatu hari jalan beberapa
  /// proyek sekaligus").
  ///
  /// Hanya ID-nya, bukan namanya: nama proyek sudah ada di telepon lewat
  /// `projectsProvider`, dan menyalinnya ke setiap baris berarti satu nama
  /// yang sama ditulis tiga puluh kali lalu menua sendiri saat kantor
  /// mengganti namanya.
  final int? projectID;

  /// Jam yang dipakai mengurutkan DAN yang ditampilkan.
  final DateTime kapan;

  /// Pekerjaannya sudah ditutup. Yang belum, jamnya adalah kabar terakhir.
  final bool selesai;

  /// Angka hasilnya: "28,90 m" atau "6 TM · 21,71 m³".
  final String utama;

  /// Baris kecil di bawahnya — nama pencatat, proyek.
  final String ket;

  /// A casting log that is open but no truck has started pouring yet:
  /// the crew is assembling the tremie, or the trucks are on their way.
  ///
  /// Requested by Daniel, 22 Nov 2026: "ini kan orang lagi persiapan cor,
  /// kenapa di activity belum muncul ya? pengen ada dong 'Preparation'".
  /// Such a log had no time at all — no truck start, no truck end — so it
  /// was skipped. Its time is now when the log was opened (`createdAt`).
  final bool preparing;

  /// Drilling: depth reached (the final depth once closed).
  final double? depthM;

  /// Drilling: metres drilled THAT DAY — the depth minus where a hole
  /// continued from an earlier day started (SP.B73: 15 -> 21 m = 6 m).
  /// Used by the day totals on the Activity page; null from an old server,
  /// which then falls back to [depthM].
  final double? metersM;

  /// Casting: concrete poured so far and the trucks it came in.
  final double? volumeM3;
  final int trucks;
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
    // A hole continued from an earlier day: only today's part counts.
    final dari = _d(m['depthStartM']);
    hasil.add(Kegiatan(
      bor: true,
      kode: '${m['pilePointCode']}',
      pilePointID: toIntOrNull(m['pilePointID']),
      projectID: toIntOrNull(m['projectID']),
      kapan: kapan,
      selesai: '${m['status']}' != 'berjalan',
      // `formatMeters` SUDAH menempelkan satuannya, berikut spasi tak
      // terputus. Ditambah ' m' lagi, hasilnya "14,00 m m" — dilaporkan
      // Daniel 19 Okt 2026.
      utama: dalam == null ? '—' : formatDepthFrom(dari, dalam),
      ket: '${m['operatorName'] ?? m['byName'] ?? ''}',
      depthM: dalam,
      metersM: _d(m['meters']),
    ));
  }

  for (final x in (jawaban['casting'] as List? ?? const [])) {
    final m = (x as Map).cast<String, Object?>();
    final open = '${m['status']}' == 'berjalan';
    // Still open with no truck started: preparing. Only an OPEN log counts —
    // a closed log without a single pour time is a broken one, and it stays
    // skipped like any other row without a time.
    final preparing = open && _jam(m['startAt']) == null;
    final kapan = _jam(m['endAt']) ??
        _jam(m['startAt']) ??
        (preparing ? _jam(m['createdAt']) : null);
    if (kapan == null || !_hariYangSama(kapan, sekarang)) continue;
    final tm = toIntOrNull(m['trucks']) ?? 0;
    final vol = _d(m['volumeM3']) ?? 0;
    hasil.add(Kegiatan(
      preparing: preparing,
      bor: false,
      kode: '${m['pilePointCode']}',
      pilePointID: toIntOrNull(m['pilePointID']),
      projectID: toIntOrNull(m['projectID']),
      kapan: kapan,
      selesai: '${m['status']}' != 'berjalan',
      // Nothing poured yet: "0 TM · 0 m³" would read as a failed pour.
      // "4 TM · 22,5 m³" (Daniel, 22 Nov 2026: dot, not ×).
      utama: preparing ? '' : '$tm TM · ${formatVolume(vol, decimals: 1)}',
      ket: '${m['byName'] ?? ''}',
      volumeM3: preparing ? null : vol,
      trucks: preparing ? 0 : tm,
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
    final proyekBeda = <int?>{for (final k in tampil) k.projectID}.toList();
    final kodeProyek = <int?, String>{
      for (final p in ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[])
        toIntOrNull(p['id']): '${p['code']}',
    };

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
              // LEBIH DARI SATU PROYEK (24 Nov 2026): baris dikelompokkan per
              // proyek, berjudul kodenya — tanpa itu dua titik "SP.B12" dari
              // dua proyek tidak dapat dibedakan. Satu proyek: tanpa judul.
              if (proyekBeda.length > 1)
                for (final pid in proyekBeda) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      kodeProyek[pid] ?? '–',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: w.muted, letterSpacing: 0.3),
                    ),
                  ),
                  for (final k in tampil.where((k) => k.projectID == pid))
                    BarisKegiatan(
                      k: k,
                      onKetuk: () => _buka(k),
                      last: k == tampil.lastWhere((x) => x.projectID == pid),
                    ),
                ]
              else
                for (final k in tampil)
                  BarisKegiatan(k: k, onKetuk: () => _buka(k), last: k == tampil.last),
              if (sisa > 0) ...[
                const SizedBox(height: 8),
                Text(
                  t(context).activityTodayMore(sisa),
                  style: TextStyle(fontSize: 12, color: w.faint),
                ),
              ],
              // PINTU KE HALAMAN AKTIVITAS. Kartu ini sengaja dipotong enam
              // baris — ia ringkasan, bukan laporan — jadi harus ada jalan
              // yang jelas menuju daftar utuhnya, berikut hari-hari
              // sebelumnya.
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.push('/activity'),
                  icon: const Icon(Icons.calendar_month, size: 18),
                  label: Text(t(context).activitySeeAll),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satu baris kegiatan — dipakai kartu beranda DAN halaman Aktivitas.
///
/// PUBLIK dengan sengaja: dua layar yang menampilkan kegiatan yang sama
/// dengan dua baris yang disusun terpisah akan menua sendiri-sendiri, lalu
/// menampilkan jam atau satuan yang berbeda untuk kejadian yang sama.
///
/// TIMELINE, redesigned at Daniel's request (22 Nov 2026: "bentuknya jelek
/// banget", then "terlalu childish ... bikin lebih mewah"). Quiet on
/// purpose — no vehicle icons, no coloured pills:
///
///     18:27  ◎  SP.B73                    15,00 m
///  terakhir  │  Anura Aldiansyah
///            │  Sedang dibor
///
///   * the TIME has its own column — "when" is the first question;
///   * the small dot carries the KIND (amber = drilling, brand = casting)
///     and is hollow with a soft halo while the work is still running;
///   * the recorder's name sits ABOVE the status (asked by Daniel), and the
///     status is a coloured WORD, not a colour alone;
///   * the figure is regular weight — the point code is what is read first.
class BarisKegiatan extends StatelessWidget {
  const BarisKegiatan({super.key, required this.k, required this.onKetuk, this.last = false});

  final Kegiatan k;
  final VoidCallback onKetuk;

  /// The last row draws no rail below its dot.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    // Ketukan baris TIDAK boleh ikut melipat kartunya: `ListCard.onTap`
    // membungkus seluruh isi, jadi barisnya memasang penadah sendiri.
    return InkWell(
      onTap: k.pilePointID == null ? null : onKetuk,
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _time(context, w),
            _rail(w),
            const SizedBox(width: 8),
            Expanded(child: _body(context, w)),
          ],
        ),
      ),
    );
  }

  Color _kindColor(TerraColors w) => k.bor ? w.warnFg : w.brand;

  Widget _time(BuildContext context, TerraColors w) {
    final caption = k.selesai
        ? t(context).activityFinished
        : k.preparing
            ? t(context).activitySince
            : t(context).activityLast;
    return SizedBox(
      width: 50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatTime(k.kapan),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: w.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(caption, style: TextStyle(fontSize: 11, color: w.faint)),
        ],
      ),
    );
  }

  Widget _rail(TerraColors w) {
    final c = _kindColor(w);
    final running = !k.selesai;
    return SizedBox(
      width: 30,
      child: Column(
        children: [
          const SizedBox(height: 4),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Hollow with a soft halo while running: the one difference
              // that is not colour alone.
              color: running ? w.surface : c,
              border: running ? Border.all(color: c, width: 2) : null,
              boxShadow: running ? [BoxShadow(color: c.withValues(alpha: 0.18), spreadRadius: 4)] : null,
            ),
          ),
          if (!last)
            Expanded(
              child: Container(
                width: 1.5,
                margin: const EdgeInsets.only(top: 5),
                color: w.border,
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, TerraColors w) {
    final (label, colour) = k.selesai
        ? (t(context).statusDone, w.okFg)
        : k.preparing
            ? (t(context).activityPreparing, w.checkedFg)
            : k.bor
                ? (t(context).stageDrilling, w.warnFg)
                : (t(context).stageCasting, w.brand);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 2 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  k.kode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: w.ink),
                ),
              ),
              if (k.utama.isNotEmpty)
                Text(
                  k.utama,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: w.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (k.ket.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              k.ket,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: w.muted),
            ),
          ],
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colour)),
        ],
      ),
    );
  }
}
