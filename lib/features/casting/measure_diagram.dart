import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';

/// Gambar kecil di atas pertanyaan: APA yang diukur.
///
/// KENAPA GAMBAR, BUKAN IKON
///
/// Sasaran aplikasi ini orang yang tidak terbiasa membaca banyak. Kalimat
/// "berapa meter pipa menyembul di atas tanah" sudah jauh lebih baik
/// daripada "kedalaman ujung tremie dari GS", tetapi ia tetap kalimat.
/// Gambar yang menunjukkan bagian mana yang dimaksud dijawab dalam sekali
/// lihat, dan tidak berubah artinya karena yang membacanya terburu-buru.
///
/// Ikon hiasan tidak mengerjakan hal itu. Yang digambar di sini SELALU
/// pengukurannya sendiri: garis tanah, lubang, dan panah pada bagian yang
/// ditanyakan.
///
/// TIDAK ADA TULISAN DI DALAM GAMBAR. Tulisan di dalam kanvas tidak ikut
/// diterjemahkan, tidak ikut membesar saat orangnya memperbesar huruf di
/// setelan HP, dan tidak terbaca pembaca layar. Kalimatnya duduk di atas
/// gambar sebagai teks biasa; gambar ini hanya menunjuk.
///
/// PALETNYA SAMA dengan `pile_section_view.dart` — tanah, lumpur, dan
/// beton harus berwarna sama di seluruh aplikasi, kalau tidak lubang di
/// dialog dan lubang di layar pantau terbaca sebagai dua benda berbeda.
class _Palet {
  static const tanah = Color(0xFFE6DCCB);
  static const garisTanah = Color(0xFFCDBFA6);
  static const lumpur = Color(0xFFDCE6EF);
  static const beton = Color(0xFF9EA5AF);
  static const betonAtas = Color(0xFFB9BFC7);
}

/// Tinggi tetap untuk seluruh gambar di dialog.
///
/// Cukup besar untuk terbaca sambil berdiri, cukup kecil supaya kolom
/// isian dan tombol tetap muat satu layar bersama papan ketik yang
/// terbuka — yang terdorong ke luar layar sama saja dengan tidak ada.
const _tinggi = 116.0;

Widget _kanvas(CustomPainter p) => SizedBox(
      height: _tinggi,
      width: double.infinity,
      child: CustomPaint(painter: p),
    );

// ───────────────────────────────────────────────────────────────────────────
// Menyembul di atas tanah
// ───────────────────────────────────────────────────────────────────────────

/// Pipa tremie menembus tanah; bagian DI ATAS tanah ditandai panah.
class StickOutDiagram extends StatelessWidget {
  const StickOutDiagram({super.key});

  @override
  Widget build(BuildContext context) => _kanvas(_StickOutPainter(context.colors));
}

class _StickOutPainter extends CustomPainter {
  _StickOutPainter(this.c);

  final TerraColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final gs = size.height * 0.34; // garis tanah
    final cx = size.width / 2;
    const lebarPipa = 16.0;

    // Tanah, dengan arsiran yang sama seperti penampang lubang.
    canvas.drawRect(Rect.fromLTRB(0, gs, size.width, size.height), Paint()..color = _Palet.tanah);
    final arsir = Paint()
      ..color = _Palet.garisTanah
      ..strokeWidth = 1;
    for (var x = 6.0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, gs + 8), Offset(x + 10, gs + 16), arsir);
    }

    // Lubang berisi lumpur.
    final lubang = Rect.fromLTRB(cx - 30, gs, cx + 30, size.height);
    canvas.drawRect(lubang, Paint()..color = _Palet.lumpur);
    canvas.drawRect(
        lubang,
        Paint()
          ..color = c.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Pipa tremie: dari atas layar menembus tanah sampai ke bawah.
    final pipa = Rect.fromLTRB(cx - lebarPipa / 2, size.height * 0.08, cx + lebarPipa / 2, size.height);
    canvas.drawRect(pipa, Paint()..color = _Palet.beton);
    canvas.drawRect(
        pipa,
        Paint()
          ..color = c.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Garis tanah ditegaskan, supaya jelas dari mana diukurnya.
    canvas.drawLine(
        Offset(0, gs),
        Offset(size.width, gs),
        Paint()
          ..color = c.ink
          ..strokeWidth = 2);

    // INI yang ditanyakan: panah dua arah pada bagian di atas tanah.
    _panahTegak(canvas, c.brand, x: cx + 46, dari: pipa.top, sampai: gs);
  }

  @override
  bool shouldRepaint(covariant _StickOutPainter old) => old.c != c;
}

// ───────────────────────────────────────────────────────────────────────────
// Sounding
// ───────────────────────────────────────────────────────────────────────────

/// Dari muka tanah turun ke muka beton.
class SoundingDiagram extends StatelessWidget {
  const SoundingDiagram({super.key});

  @override
  Widget build(BuildContext context) => _kanvas(_SoundingPainter(context.colors));
}

class _SoundingPainter extends CustomPainter {
  _SoundingPainter(this.c);

  final TerraColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final gs = size.height * 0.16;
    final cx = size.width / 2;
    final mukaBeton = size.height * 0.62;

    canvas.drawRect(Rect.fromLTRB(0, gs, size.width, size.height), Paint()..color = _Palet.tanah);
    final arsir = Paint()
      ..color = _Palet.garisTanah
      ..strokeWidth = 1;
    for (var x = 6.0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, gs + 10), Offset(x + 10, gs + 18), arsir);
    }

    final lubang = Rect.fromLTRB(cx - 32, gs, cx + 32, size.height);
    canvas.drawRect(lubang, Paint()..color = _Palet.lumpur);

    // Beton di dasar lubang, dengan permukaan yang sedikit bergelombang —
    // bentuk yang sama dengan penampang di layar pantau.
    final atas = Path()..moveTo(lubang.left, mukaBeton);
    for (var x = lubang.left; x <= lubang.right; x += 3) {
      atas.lineTo(x, mukaBeton + math.sin((x - lubang.left) / lubang.width * 2 * math.pi * 1.5) * 1.6);
    }
    atas
      ..lineTo(lubang.right, size.height)
      ..lineTo(lubang.left, size.height)
      ..close();
    canvas.drawPath(
        atas,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_Palet.betonAtas, _Palet.beton],
          ).createShader(Rect.fromLTRB(lubang.left, mukaBeton, lubang.right, size.height)));

    canvas.drawRect(
        lubang,
        Paint()
          ..color = c.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawLine(
        Offset(0, gs),
        Offset(size.width, gs),
        Paint()
          ..color = c.ink
          ..strokeWidth = 2);

    // INI yang ditanyakan: dari garis tanah turun ke muka beton.
    _panahTegak(canvas, c.brand, x: cx + 48, dari: gs, sampai: mukaBeton);
  }

  @override
  bool shouldRepaint(covariant _SoundingPainter old) => old.c != c;
}

// ───────────────────────────────────────────────────────────────────────────
// Slump
// ───────────────────────────────────────────────────────────────────────────

/// Kerucut uji dan beton yang merosot — penurunannya yang ditanyakan.
///
/// Gambar ini sekaligus menjawab pertanyaan yang tidak diucapkan: angka
/// yang diminta berasal dari KERUCUT DI LOKASI, bukan dari angka yang
/// tercetak di surat jalan.
class SlumpDiagram extends StatelessWidget {
  const SlumpDiagram({super.key});

  @override
  Widget build(BuildContext context) => _kanvas(_SlumpPainter(context.colors));
}

class _SlumpPainter extends CustomPainter {
  _SlumpPainter(this.c);

  final TerraColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final dasar = size.height - 14;
    final puncak = size.height * 0.18;
    final kiri = size.width / 2 - 70;
    final kanan = size.width / 2 + 16;

    // Alas tempat kerucut berdiri.
    canvas.drawLine(
        Offset(kiri - 14, dasar),
        Offset(kanan + 60, dasar),
        Paint()
          ..color = c.ink
          ..strokeWidth = 2);

    // Kerucut: trapesium, lebar di bawah.
    final kerucut = Path()
      ..moveTo(kiri - 26, dasar)
      ..lineTo(kiri + 26, dasar)
      ..lineTo(kiri + 12, puncak)
      ..lineTo(kiri - 12, puncak)
      ..close();
    canvas.drawPath(kerucut, Paint()..color = _Palet.lumpur);
    canvas.drawPath(
        kerucut,
        Paint()
          ..color = c.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);

    // Beton yang sudah dikeluarkan dan merosot.
    final merosot = dasar - (dasar - puncak) * 0.45;
    final gundukan = Path()
      ..moveTo(kanan - 8, dasar)
      ..quadraticBezierTo(kanan + 2, merosot, kanan + 26, merosot)
      ..quadraticBezierTo(kanan + 52, merosot, kanan + 60, dasar)
      ..close();
    canvas.drawPath(gundukan, Paint()..color = _Palet.beton);

    // Garis putus-putus setinggi kerucut, sebagai acuan penurunannya.
    final putus = Paint()
      ..color = _Palet.garisTanah
      ..strokeWidth = 1.5;
    for (var x = kiri + 12; x < kanan + 62; x += 8) {
      canvas.drawLine(Offset(x, puncak), Offset(x + 4, puncak), putus);
    }

    // INI yang ditanyakan: seberapa turun dari tinggi kerucut.
    _panahTegak(canvas, c.brand, x: kanan + 26, dari: puncak, sampai: merosot);
  }

  @override
  bool shouldRepaint(covariant _SlumpPainter old) => old.c != c;
}

// ───────────────────────────────────────────────────────────────────────────

/// Panah dua arah tegak — satu-satunya penanda "ini yang ditanya".
///
/// Bentuknya sengaja SATU untuk ketiga gambar: yang sudah mengerti panah
/// ini di satu pertanyaan tidak perlu menebak lagi di pertanyaan berikutnya.
void _panahTegak(Canvas canvas, Color warna, {required double x, required double dari, required double sampai}) {
  final p = Paint()
    ..color = warna
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(x, dari), Offset(x, sampai), p);
  const s = 5.0;
  for (final (y, arah) in [(dari, 1.0), (sampai, -1.0)]) {
    canvas.drawLine(Offset(x, y), Offset(x - s, y + s * arah), p);
    canvas.drawLine(Offset(x, y), Offset(x + s, y + s * arah), p);
  }
  // Garis tipis mendatar di kedua ujung, supaya jelas panahnya menunjuk
  // SAMPAI mana — bukan sekadar melayang di sebelah gambar.
  final tipis = Paint()
    ..color = warna
    ..strokeWidth = 1.2;
  canvas.drawLine(Offset(x - 12, dari), Offset(x + 12, dari), tipis);
  canvas.drawLine(Offset(x - 12, sampai), Offset(x + 12, sampai), tipis);
}
