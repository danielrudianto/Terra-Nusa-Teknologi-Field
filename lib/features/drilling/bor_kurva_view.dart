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
  const KurvaBor({super.key, required this.titik, required this.ringkas});

  final List<TitikKurvaBor> titik;
  final RingkasBor ringkas;

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
          height: 170,
          child: CustomPaint(
            size: Size.infinite,
            painter: _KurvaPainter(
              titik: titik,
              colors: w,
              // RENTANG berhenti, bukan jam mulainya saja.
              //
              // Sejak ruas mandek yang berurutan digabung
              // (`gabungBerhenti`), satu berhenti dapat memuat beberapa
              // bacaan di tengahnya — justru karena engineer diminta tetap
              // mengabarkan selama rig diam. Dikenali dari jam mulai saja,
              // hanya potongan pertama yang terwarnai dan sisanya tampak
              // seperti pengeboran yang sangat lambat.
              //
              // Dikirim dari ringkasan yang sama dengan angka di atasnya,
              // supaya garis dan tulisannya tidak dapat berbeda.
              berhenti: [
                for (final r in ringkas.berhenti) (r.dariWaktu, r.sampaiWaktu),
              ],
            ),
          ),
        ),
      ],
    );
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
  });

  final List<TitikKurvaBor> titik;
  final TerraColors colors;

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
    final skalaDalam = dalamMaks <= 0 ? 1.0 : dalamMaks * 1.06;

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
      !listEquals(old.berhenti, berhenti);
}
