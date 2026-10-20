import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/util/format.dart';
import 'bor_kurva.dart';

/// KURVA KEDALAMAN vs WAKTU satu log bor, beserta angka ringkasannya.
///
/// Digambar sendiri dengan [CustomPainter], bukan dengan pustaka grafik.
/// Aplikasi ini sudah menggambar penampang lubang dengan cara yang sama
/// (`pile_section_view.dart`), dan satu kurva garis tidak sepadan dengan
/// menambah dependensi yang membawa gayanya sendiri ke layar yang seluruh
/// sisanya memakai token warna aplikasi.
class KurvaBor extends StatelessWidget {
  const KurvaBor({
    super.key,
    required this.titik,
    required this.ringkas,
    this.skalaDalamM,
    this.rencanaM,
    this.waktuDipilih,
    this.onKetuk,
  });

  final List<TitikKurvaBor> titik;
  final RingkasBor ringkas;

  /// Kedalaman di dasar sumbu. `null` = sumbunya menyesuaikan bacaan
  /// terdalam.
  ///
  /// DIMINTA DANIEL, 19 Oktober 2026: sumbunya dibuat sampai kedalaman
  /// RENCANA + 5 m. Dengan begitu kurva menjawab pertanyaan yang sebenarnya
  /// — "sudah sampai mana dari yang direncanakan" — dan, karena penampang
  /// di sebelahnya memakai angka yang sama, keduanya sejajar: satu garis
  /// mendatar di layar berarti kedalaman yang sama pada dua gambar.
  final double? skalaDalamM;

  /// Panjang bor RENCANA — digambar sebagai garis acuan.
  final double? rencanaM;

  /// `waktu` bacaan yang sedang disorot, atau `null`.
  final int? waktuDipilih;

  /// Dipanggil saat sebuah bacaan diketuk pada kurvanya.
  final void Function(int waktu)? onKetuk;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Empat angka yang menjawab pertanyaan yang dibawa ke rapat, di ATAS
        // kurvanya: yang membaca sekilas tidak perlu menakar grafik.
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            _Sel(t(context).deepestLabel, formatMeters(ringkas.kedalamanM)),
            // DURASI EFEKTIF di depan, TOTAL kecil di bawahnya — SAMA DENGAN
            // WEB (`riwayat-titik-dialog`).
            //
            // Waktu berhenti bukan waktu mengebor. Satu angka saja — bacaan
            // pertama sampai terakhir — membuat titik yang bornya cepat
            // tetapi lama menunggu material terbaca persis seperti titik yang
            // bornya pelan sepanjang hari, dan angka itu dibawa ke rapat
            // sebagai ukuran kinerja.
            //
            // Totalnya TETAP ada, tidak diganti: "titik ini selesai berapa
            // lama" pertanyaan yang juga nyata, hanya bukan yang sama.
            _Sel(
              t(context).drillEffectiveLabel,
              _jam(ringkas.durasiEfektifJam),
              bawah: t(context).drillOfTotal(_jam(ringkas.durasiJam)),
            ),
            _Sel(
              t(context).drillEffectiveRateLabel,
              _laju(context, ringkas.lajuEfektifMPerJam),
              bawah: ringkas.lajuRataMPerJam == null
                  ? null
                  : t(context).drillRateTotal(
                      ringkas.lajuRataMPerJam!.toStringAsFixed(1).replaceAll('.', ','),
                    ),
            ),
            if (ringkas.ruasTerlambat != null)
              _Sel(
                t(context).slowestSegmentLabel,
                _laju(context, ringkas.ruasTerlambat!.lajuMPerJam),
                warna: w.warnFg,
                bawah: _rentang(ringkas.ruasTerlambat!),
              ),
          ],
        ),
        // BERHENTINYA DISEBUT SATU PER SATU, dengan jamnya.
        //
        // "berhenti 4 j 40 m" saja tidak dapat ditindaklanjuti siapa pun;
        // "11.20–14.00" dapat dicocokkan dengan kejadian hari itu — material
        // telat, hujan, rig pindah. Yang lebih pendek dari [menitBerhenti]
        // tidak ikut: menyebut sambungan pipa lima menit sebagai "berhenti"
        // membuat daftarnya berhenti dibaca.
        if (ringkas.berhenti.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            t(context).drillStops(
              '${ringkas.berhenti.length}',
              _jam(ringkas.durasiBerhentiJam),
            ),
            style: TextStyle(color: w.warnFg, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              for (final r in ringkas.berhenti)
                Text(
                  '${_rentang(r)} (${_jam(r.jam)})',
                  style: TextStyle(color: w.muted, fontSize: 11.5),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: tinggiKanvas,
          child: LayoutBuilder(
            builder: (context, kotak) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              // KETUKAN DICARI BACAAN TERDEKATNYA MENURUT WAKTU (sumbu X)
              // saja, bukan menurut jarak dua sumbu.
              //
              // Pada kurva yang curam, dua bacaan dapat berdekatan di layar
              // tetapi berjauhan jamnya; yang mengetuk selalu menunjuk
              // "bacaan jam sekian", dan itu pertanyaan satu sumbu.
              onTapUp: (d) => _ketuk(d.localPosition.dx, kotak.maxWidth),
              child: CustomPaint(
                size: Size.infinite,
                painter: _KurvaPainter(
                  titik: titik,
                  colors: w,
                  skalaDalamM: skalaDalamM,
                  rencanaM: rencanaM,
                  // Labelnya dirakit DI SINI, bukan di painter: painter
                  // tidak punya `BuildContext`, dan teks yang diketik
                  // langsung di painter lolos dari seluruh pemeriksa
                  // terjemahan.
                  labelRencana: rencanaM == null
                      ? null
                      : t(context).drillPlanRef(formatMeters(rencanaM)),
                  // RENTANG berhenti, bukan jam mulainya saja. Sejak ruas
                  // mandek yang berurutan digabung (`gabungBerhenti`), satu
                  // berhenti dapat memuat beberapa bacaan di tengahnya —
                  // justru karena engineer diminta tetap mengabarkan selama
                  // rig diam. Dikenali dari jam mulai saja, hanya potongan
                  // pertama yang terwarnai dan sisanya tampak seperti
                  // pengeboran yang sangat lambat.
                  waktuDipilih: waktuDipilih,
                  berhenti: [
                    for (final r in ringkas.berhenti)
                      (r.dariWaktu, r.sampaiWaktu),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tinggi kanvas kurva.
  static const tinggiKanvas = 170.0;

  /// Tepi kiri kanvas — HARUS sama dengan `kiri` di painternya, sebab
  /// ketukan diubah menjadi waktu memakai pemetaan yang sama.
  static const _kiri = 38.0;

  void _ketuk(double dx, double lebarKotak) {
    final panggil = onKetuk;
    if (panggil == null || titik.length < 2) return;
    final lebar = lebarKotak - _kiri - 6;
    if (lebar <= 0) return;

    final t0 = titik.first.waktu;
    final t1 = titik.last.waktu;
    final rentang = (t1 - t0).toDouble();
    if (rentang <= 0) return;

    final waktu = t0 + ((dx - _kiri) / lebar * rentang).round();
    var pilih = titik.first;
    var jarak = (waktu - pilih.waktu).abs();
    for (final p in titik.skip(1)) {
      final j = (waktu - p.waktu).abs();
      if (j < jarak) {
        jarak = j;
        pilih = p;
      }
    }
    panggil(pilih.waktu);
  }

  static String _jam(double? v) =>
      v == null ? '–' : formatDuration(Duration(milliseconds: (v * 3600000).round()));

  static String _laju(BuildContext context, double? v) =>
      v == null ? '–' : t(context).metresPerHour(v.toStringAsFixed(1).replaceAll('.', ','));

  static String _rentang(RuasBor r) =>
      '${formatTime(DateTime.fromMillisecondsSinceEpoch(r.dariWaktu))}'
      '–${formatTime(DateTime.fromMillisecondsSinceEpoch(r.sampaiWaktu))}';
}

class _Sel extends StatelessWidget {
  const _Sel(this.label, this.nilai, {this.warna, this.bawah});

  final String label;
  final String nilai;
  final Color? warna;
  final String? bawah;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: w.muted, fontSize: 12)),
        Text(nilai, style: TextStyle(fontWeight: FontWeight.w700, color: warna ?? w.ink)),
        if (bawah != null) Text(bawah!, style: TextStyle(color: w.faint, fontSize: 11.5)),
      ],
    );
  }
}

class _KurvaPainter extends CustomPainter {
  _KurvaPainter({
    required this.titik,
    required this.colors,
    required this.berhenti,
    this.skalaDalamM,
    this.rencanaM,
    this.labelRencana,
    this.waktuDipilih,
  });

  final List<TitikKurvaBor> titik;
  final TerraColors colors;

  /// Kedalaman di dasar sumbu; `null` = menyesuaikan bacaan terdalam.
  final double? skalaDalamM;

  /// Panjang bor rencana — garis acuannya.
  final double? rencanaM;

  /// Tulisan di garis acuannya, sudah diterjemahkan.
  final String? labelRencana;

  /// `waktu` bacaan yang sedang disorot.
  final int? waktuDipilih;

  /// Rentang `(dari, sampai)` tiap berhenti, dalam milidetik.
  final List<(int, int)> berhenti;

  @override
  void paint(Canvas canvas, Size size) {
    if (titik.length < 2) return;

    const kiri = 38.0; // ruang skala kedalaman
    const bawah = 18.0; // ruang label jam
    const atas = 8.0;
    final kanan = size.width - 6;
    final lebar = kanan - kiri;
    final tinggi = size.height - atas - bawah;
    if (lebar <= 0 || tinggi <= 0) return;

    final t0 = titik.first.waktu;
    final t1 = titik.last.waktu;
    final rentang = (t1 - t0).toDouble();
    final dalamMaks = titik.map((p) => p.dalam).reduce((a, b) => a > b ? a : b);
    // Sedikit ruang di bawah titik terdalam supaya penanda terakhirnya tidak
    // menempel di tepi dan terbaca sebagai terpotong.
    // Sumbunya dipaksa sampai [skalaDalamM] bila ada — biasanya kedalaman
    // RENCANA + 5 m. Dengan begitu kurva menjawab "sudah sampai mana dari
    // yang direncanakan", bukan hanya "bagaimana bentuk pengeborannya".
    //
    // `math.max` dengan bacaan terdalam: titik yang dibor LEWAT rencana
    // tidak boleh keluar dari gambarnya sendiri.
    final skalaDalam = skalaDalamM != null && skalaDalamM! > 0
        ? math.max(skalaDalamM!, dalamMaks <= 0 ? 1.0 : dalamMaks * 1.02)
        : (dalamMaks <= 0 ? 1.0 : dalamMaks * 1.06);

    double x(int ms) => rentang <= 0 ? kiri : kiri + (ms - t0) / rentang * lebar;
    // Sumbu Y DIBALIK: kedalaman bertambah ke BAWAH, seperti lubangnya.
    // Digambar naik, kurvanya terbaca sebagai sesuatu yang bertumbuh ke atas
    // — dan yang membacanya sekilas menyimpulkan arah yang berlawanan dengan
    // kenyataan.
    double y(double m) => atas + (m / skalaDalam) * tinggi;

    final garisBantu = Paint()
      ..color = colors.line
      ..strokeWidth = 1;

    // Empat garis bantu kedalaman, berlabel.
    for (var i = 0; i <= 4; i++) {
      final m = skalaDalam * i / 4;
      final yy = y(m);
      canvas.drawLine(Offset(kiri, yy), Offset(kanan, yy), garisBantu);
      _teks(canvas, formatMeters(m), Offset(0, yy - 7), kiri - 6, colors.faint,
          align: TextAlign.right);
    }

    // Jam pertama dan terakhir saja: sumbu yang penuh label pada layar
    // selebar telapak tangan menjadi deretan angka yang saling menimpa.
    _teks(canvas, formatTime(DateTime.fromMillisecondsSinceEpoch(t0)),
        Offset(kiri, size.height - bawah + 3), 56, colors.faint);
    _teks(canvas, formatTime(DateTime.fromMillisecondsSinceEpoch(t1)),
        Offset(kanan - 56, size.height - bawah + 3), 56, colors.faint,
        align: TextAlign.right);

    // Garis LURUS antar bacaan, sama dengan grafik di web. Garis melengkung
    // menyiratkan kedalaman di antara dua bacaan, padahal tidak ada yang
    // mengukurnya; pada jeda tiga jam lengkungnya bahkan menggambar lubang
    // yang lebih dalam daripada yang pernah tercatat.
    final jalur = Path()..moveTo(x(titik.first.waktu), y(titik.first.dalam));
    for (final p in titik.skip(1)) {
      jalur.lineTo(x(p.waktu), y(p.dalam));
    }

    final isi = Path.from(jalur)
      ..lineTo(x(titik.last.waktu), atas)
      ..lineTo(x(titik.first.waktu), atas)
      ..close();
    canvas.drawPath(isi, Paint()..color = colors.brand.withValues(alpha: 0.10));

    // RUAS BERHENTI DIWARNAI LAIN, bukan digambar sewarna.
    //
    // Pada kurva sewarna, berhenti tampak sebagai garis datar yang panjang —
    // dan garis datar yang panjang juga bentuk pengeboran yang sangat
    // lambat. Dua keadaan yang penanganannya berbeda tidak boleh berwujud
    // sama. Latarnya diberi blok redup supaya terbaca sebagai RENTANG WAKTU,
    // bukan sebagai satu bacaan yang ganjil.
    final catBor = Paint()
      ..color = colors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final catBerhenti = Paint()
      ..color = colors.warnFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final blokBerhenti = Paint()..color = colors.warnFg.withValues(alpha: 0.10);

    for (var i = 1; i < titik.length; i++) {
      final a = titik[i - 1];
      final b = titik[i];
      // Ruas dianggap bagian dari berhenti bila ia berada DI DALAM salah
      // satu rentangnya — termasuk ruas di antara dua bacaan yang
      // dikirimkan selama berhenti berlangsung.
      final diam = berhenti.any((r) => a.waktu >= r.$1 && b.waktu <= r.$2);
      if (diam) {
        canvas.drawRect(
          Rect.fromLTRB(x(a.waktu), atas, x(b.waktu), atas + tinggi),
          blokBerhenti,
        );
      }
      canvas.drawLine(
        Offset(x(a.waktu), y(a.dalam)),
        Offset(x(b.waktu), y(b.dalam)),
        diam ? catBerhenti : catBor,
      );
    }

    final penanda = Paint()..color = colors.brand;
    for (final p in titik) {
      canvas.drawCircle(Offset(x(p.waktu), y(p.dalam)), 2.5, penanda);
    }

    // BACAAN YANG DISOROT: cincin, bukan titik yang dibesarkan.
    //
    // Dibesarkan saja, ia hanya tampak sebagai bacaan yang entah kenapa
    // lebih tebal; cincin di sekelilingnya terbaca sebagai "yang ini",
    // dan tetap terbaca walau jatuh di tengah rombongan bacaan rapat.
    // Garis tegaknya menyambungkan bacaan itu ke sumbu waktu, supaya
    // jamnya dapat dibaca tanpa menakar.
    final sorot = waktuDipilih;
    if (sorot != null) {
      for (final p in titik) {
        if (p.waktu != sorot) continue;
        final titikSorot = Offset(x(p.waktu), y(p.dalam));
        canvas.drawLine(
          Offset(titikSorot.dx, atas),
          Offset(titikSorot.dx, size.height - bawah),
          Paint()
            ..color = colors.brand.withValues(alpha: 0.35)
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          titikSorot,
          6,
          Paint()
            ..color = colors.brand
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }

    // GARIS ACUAN TIP RENCANA — digambar PALING AKHIR, di atas kurvanya.
    //
    // Diminta Daniel, 19 Oktober 2026: "dikasih reference line buat kasih
    // tau design tip level nya sampai mana".
    //
    // Inilah yang membuat sumbu sampai rencana + 5 m berarti: tanpa
    // garisnya, ruang kosong di bawah kurva hanya ruang kosong; dengan
    // garisnya, ruang itu menjadi SISA YANG HARUS DIBOR, terbaca tanpa
    // menghitung apa pun.
    //
    // Di atas kurva, bukan di bawahnya: garis acuan yang tertutup kurva
    // justru hilang tepat pada titik yang hampir selesai — yaitu saat ia
    // paling dicari.
    final rencana = rencanaM;
    if (rencana != null && rencana > 0 && rencana <= skalaDalam) {
      final yy = y(rencana);
      _putusPutus(canvas, Offset(kiri, yy), Offset(kanan, yy), colors.warnFg);
      _teks(
        canvas,
        labelRencana ?? formatMeters(rencana),
        Offset(kiri + 4, yy + 3),
        lebar - 8,
        colors.warnFg,
      );
    }
  }

  void _putusPutus(Canvas canvas, Offset a, Offset b, Color warna) {
    final cat = Paint()
      ..color = warna
      ..strokeWidth = 1.2;
    final jarak = (b - a).distance;
    if (jarak <= 0) return;
    final arah = (b - a) / jarak;
    for (var t = 0.0; t < jarak; t += 7) {
      canvas.drawLine(
          a + arah * t, a + arah * (t + 4 > jarak ? jarak : t + 4), cat);
    }
  }

  void _teks(Canvas canvas, String teks, Offset di, double lebar, Color warna,
      {TextAlign align = TextAlign.left}) {
    TextPainter(
      text: TextSpan(
        text: teks,
        style: TextStyle(
            fontFamily: 'Montserrat', fontSize: 10.5, color: warna, fontWeight: FontWeight.w500),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )
      ..layout(minWidth: lebar, maxWidth: lebar)
      ..paint(canvas, di);
  }

  @override
  bool shouldRepaint(covariant _KurvaPainter old) =>
      old.titik != titik ||
      old.colors != colors ||
      old.skalaDalamM != skalaDalamM ||
      old.rencanaM != rencanaM ||
      old.labelRencana != labelRencana ||
      old.waktuDipilih != waktuDipilih ||
      !listEquals(old.berhenti, berhenti);
}
