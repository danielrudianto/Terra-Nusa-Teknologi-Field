import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';
import '../../core/util/format.dart';

/// PENAMPANG LUBANG YANG SEDANG DIBOR — pasangan `PileSectionView`.
///
/// DIMINTA DANIEL, 19 Oktober 2026: "animasi yang cor bagus banget bang,
/// boleh ga gw minta animasi juga waktu bor?"
///
/// Aturannya disalin dari penampang cor, dan dua di antaranya bukan soal
/// gaya:
///
///   * SKALA HANYA PADA KEDALAMAN. Lebar lubang tidak berskala — digambar
///     seukuran aslinya, lubang 800 mm pada lubang sedalam 30 m menjadi
///     garis setebal rambut, dan tidak ada yang dapat dibaca darinya;
///
///   * BERGERAK HANYA SELAMA MENGEBOR. Gambar diam tidak memakan baterai,
///     dan — lebih penting — animasi yang tetap berputar ketika rig
///     sebenarnya berhenti adalah layar yang BERBOHONG dengan cara yang
///     paling meyakinkan: yang melihatnya dari kantor menyimpulkan
///     pekerjaan sedang berjalan.
///
/// Mata bor digambar pada KEDALAMAN TERAKHIR YANG TERCATAT, bukan ditebak
/// maju menurut waktu. Lubang ini dibayar per meter, dan gambar yang
/// menebak lebih dalam daripada yang tercatat adalah gambar yang mendahului
/// catatannya sendiri.
class BorSectionView extends StatefulWidget {
  const BorSectionView({
    super.key,
    required this.kedalamanM,
    required this.rencanaM,
    required this.berjalan,
    required this.diam,
  });

  /// Kedalaman terakhir yang tercatat.
  final double kedalamanM;

  /// Panjang bor rencana. `null` = tidak diketahui; lubangnya lalu digambar
  /// sepenuh kotak tanpa garis sasaran, bukan dengan sasaran tebakan.
  final double? rencanaM;

  /// Log bornya masih terbuka.
  final bool berjalan;

  /// Sedang BERHENTI — tidak ada kemajuan sejak beberapa waktu lalu.
  final bool diam;

  @override
  State<BorSectionView> createState() => _BorSectionViewState();
}

class _BorSectionViewState extends State<BorSectionView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _putar =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  bool get _hidup => widget.berjalan && !widget.diam;

  @override
  void initState() {
    super.initState();
    if (_hidup) _putar.repeat();
  }

  @override
  void didUpdateWidget(BorSectionView old) {
    super.didUpdateWidget(old);
    if (_hidup && !_putar.isAnimating) {
      _putar.repeat();
    } else if (!_hidup && _putar.isAnimating) {
      _putar.stop();
    }
  }

  @override
  void dispose() {
    _putar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Container(
      height: 210,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: w.line),
      ),
      child: AnimatedBuilder(
        animation: _putar,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BorPainter(
            kedalamanM: widget.kedalamanM,
            rencanaM: widget.rencanaM,
            fase: _putar.value,
            hidup: _hidup,
            diam: widget.diam,
            colors: w,
          ),
        ),
      ),
    );
  }
}

class _BorPainter extends CustomPainter {
  _BorPainter({
    required this.kedalamanM,
    required this.rencanaM,
    required this.fase,
    required this.hidup,
    required this.diam,
    required this.colors,
  });

  final double kedalamanM;
  final double? rencanaM;

  /// 0..1, satu putaran penuh ulir.
  final double fase;
  final bool hidup;
  final bool diam;
  final TerraColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const kiri = 46.0; // ruang skala kedalaman
    const atas = 20.0; // ruang batang bor di atas tanah
    final bawah = size.height - 10;
    final tinggi = bawah - atas;
    if (tinggi <= 0 || size.width <= kiri + 20) return;

    final tengah = kiri + (size.width - kiri) / 2;
    // `clamp` dideklarasikan di `num` dan memulangkan `num`; dibiarkan
    // begitu, ia menular ke setiap hitungan di bawahnya dan baru ditolak
    // di `Rect.fromLTRB` yang menuntut `double`.
    final double lebarLubang =
        ((size.width - kiri) * 0.42).clamp(26.0, 74.0).toDouble();

    // SKALANYA: rencana bila ada, kalau tidak kedalaman sekarang dengan
    // sedikit ruang di bawahnya supaya mata bornya tidak menempel di tepi.
    // `1.0`, bukan `1`: `math.max(double, int)` menyimpulkan `num`, dan
    // `num` lalu menular ke `clamp` di bawahnya — yang menolak masuk ke
    // parameter `double`.
    final double skala = (rencanaM != null && rencanaM! > 0)
        ? math.max(rencanaM!, kedalamanM)
        : math.max(kedalamanM * 1.15, 1.0);

    double y(double m) => atas + (m / skala) * tinggi;
    final yBor = y(kedalamanM.clamp(0.0, skala).toDouble());

    // ---- tanah ----
    final tanah = Paint()..color = colors.muted.withValues(alpha: 0.10);
    canvas.drawRect(
      Rect.fromLTRB(kiri, atas, size.width, bawah),
      tanah,
    );
    canvas.drawLine(
      const Offset(kiri, atas),
      Offset(size.width, atas),
      Paint()
        ..color = colors.muted
        ..strokeWidth = 1.6,
    );
    // Arsir permukaan tanah — tanda baku gambar potongan.
    for (var x = kiri; x < size.width; x += 9) {
      canvas.drawLine(
        Offset(x, atas),
        Offset(x - 5, atas - 5),
        Paint()
          ..color = colors.faint
          ..strokeWidth = 1,
      );
    }

    // ---- lubang yang sudah ada ----
    final lubang = Rect.fromLTRB(
      tengah - lebarLubang / 2,
      atas,
      tengah + lebarLubang / 2,
      yBor,
    );
    canvas.drawRect(lubang, Paint()..color = colors.pageBg);
    canvas.drawRect(
      lubang,
      Paint()
        ..color = colors.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // ---- sisa sampai rencana: GARIS PUTUS, bukan lubang ----
    //
    // Yang belum dibor tidak boleh berwujud sama dengan yang sudah; dari
    // kantor, keduanya dibaca sebagai kemajuan.
    if (rencanaM != null && rencanaM! > kedalamanM) {
      final yRencana = y(rencanaM!);
      _putusPutus(
        canvas,
        Offset(tengah - lebarLubang / 2, yBor),
        Offset(tengah - lebarLubang / 2, yRencana),
        colors.faint,
      );
      _putusPutus(
        canvas,
        Offset(tengah + lebarLubang / 2, yBor),
        Offset(tengah + lebarLubang / 2, yRencana),
        colors.faint,
      );
      _putusPutus(
        canvas,
        Offset(tengah - lebarLubang / 2 - 6, yRencana),
        Offset(tengah + lebarLubang / 2 + 6, yRencana),
        colors.faint,
      );
      _teks(canvas, formatMeters(rencanaM), Offset(0, yRencana - 7), kiri - 6,
          colors.faint,
          align: TextAlign.right);
    }

    // ---- batang bor + ulir ----
    final warnaBor = diam ? colors.warnFg : colors.brand;
    final batang = Paint()
      ..color = warnaBor
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(tengah, 2), Offset(tengah, yBor), batang);

    // ULIRNYA bergerak TURUN sepanjang batang, bukan berputar di tempat:
    // yang dilihat orang dari luar adalah tanah terangkat ke atas, jadi
    // ulir yang bergerak ke bawah membaca sebagai bor yang menekan masuk.
    const jarak = 11.0;
    final geser = fase * jarak;
    final ulir = Paint()
      ..color = warnaBor.withValues(alpha: hidup ? 0.95 : 0.45)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final lebarUlir = lebarLubang * 0.34;
    for (var yy = atas + geser; yy < yBor - 2; yy += jarak) {
      if (yy < atas) continue;
      canvas.drawLine(
        Offset(tengah - lebarUlir, yy),
        Offset(tengah + lebarUlir, yy + jarak * 0.42),
        ulir,
      );
    }

    // Mata bor: segitiga kecil di ujungnya.
    canvas.drawPath(
      Path()
        ..moveTo(tengah - lebarUlir - 1, yBor - 7)
        ..lineTo(tengah + lebarUlir + 1, yBor - 7)
        ..lineTo(tengah, yBor + 4)
        ..close(),
      Paint()..color = warnaBor,
    );

    // ---- skala kedalaman ----
    for (var i = 0; i <= 4; i++) {
      final m = skala * i / 4;
      final yy = y(m);
      canvas.drawLine(
        Offset(kiri - 3, yy),
        Offset(kiri, yy),
        Paint()
          ..color = colors.faint
          ..strokeWidth = 1,
      );
      _teks(canvas, formatMeters(m), Offset(0, yy - 7), kiri - 6, colors.faint,
          align: TextAlign.right);
    }

    // ---- kedalaman sekarang, menempel pada mata bornya ----
    _teks(
      canvas,
      formatMeters(kedalamanM),
      Offset(tengah + lebarLubang / 2 + 8, yBor - 8),
      size.width - (tengah + lebarLubang / 2 + 8),
      warnaBor,
      tebal: true,
    );
  }

  void _putusPutus(Canvas canvas, Offset a, Offset b, Color warna) {
    final cat = Paint()
      ..color = warna
      ..strokeWidth = 1.2;
    final jarak = (b - a).distance;
    if (jarak <= 0) return;
    final arah = (b - a) / jarak;
    for (var t = 0.0; t < jarak; t += 7) {
      final p1 = a + arah * t;
      final p2 = a + arah * (t + 4 > jarak ? jarak : t + 4);
      canvas.drawLine(p1, p2, cat);
    }
  }

  void _teks(Canvas canvas, String teks, Offset di, double lebar, Color warna,
      {TextAlign align = TextAlign.left, bool tebal = false}) {
    if (lebar <= 0) return;
    TextPainter(
      text: TextSpan(
        text: teks,
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 11,
          color: warna,
          fontWeight: tebal ? FontWeight.w800 : FontWeight.w500,
        ),
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
  bool shouldRepaint(covariant _BorPainter old) =>
      old.fase != fase ||
      old.kedalamanM != kedalamanM ||
      old.rencanaM != rencanaM ||
      old.hidup != hidup ||
      old.diam != diam ||
      old.colors != colors;
}
