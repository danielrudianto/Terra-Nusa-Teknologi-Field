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
            _Sel(t(context).drillDurationLabel, _jam(ringkas.durasiJam)),
            _Sel(t(context).avgRateLabel, _laju(context, ringkas.lajuRataMPerJam)),
            if (ringkas.ruasTerlambat != null)
              _Sel(
                t(context).slowestSegmentLabel,
                _laju(context, ringkas.ruasTerlambat!.lajuMPerJam),
                warna: w.warnFg,
                bawah: _rentang(ringkas.ruasTerlambat!),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: CustomPaint(
            size: Size.infinite,
            painter: _KurvaPainter(titik: titik, colors: w),
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
  _KurvaPainter({required this.titik, required this.colors});

  final List<TitikKurvaBor> titik;
  final TerraColors colors;

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

    final jalur = Path()..moveTo(x(titik.first.waktu), y(titik.first.dalam));
    for (final p in titik.skip(1)) {
      // Garis LURUS antar bacaan, sama dengan grafik di web. Garis melengkung
      // menyiratkan kedalaman di antara dua bacaan, padahal tidak ada yang
      // mengukurnya; pada jeda tiga jam lengkungnya bahkan menggambar lubang
      // yang lebih dalam daripada yang pernah tercatat.
      jalur.lineTo(x(p.waktu), y(p.dalam));
    }

    final isi = Path.from(jalur)
      ..lineTo(x(titik.last.waktu), atas)
      ..lineTo(x(titik.first.waktu), atas)
      ..close();
    canvas.drawPath(isi, Paint()..color = colors.brand.withValues(alpha: 0.10));
    canvas.drawPath(
      jalur,
      Paint()
        ..color = colors.brand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

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
      old.titik != titik || old.colors != colors;
}
