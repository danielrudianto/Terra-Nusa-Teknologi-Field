import 'package:flutter/material.dart';

/// Token warna TerraBot — SALINAN dari `src/styles.scss` frontend Angular.
///
/// Nama mengikuti variabel CSS-nya (`--brand`, `--warn-bg`, ...), supaya
/// yang menyamakan keduanya kelak cukup mencari nama yang sama. Bila warna
/// di web diubah, ubah juga di sini — tidak ada yang menyalinnya otomatis.
@immutable
class WarnaTerra extends ThemeExtension<WarnaTerra> {
  const WarnaTerra({
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.onBrand,
    required this.pageBg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.border,
    required this.warnBg,
    required this.warnFg,
    required this.badBg,
    required this.badFg,
    required this.okBg,
    required this.okFg,
    required this.infoBg,
    required this.infoFg,
    required this.checkedBg,
    required this.checkedFg,
    required this.bayangan,
  });

  final Color brand;
  final Color brandStrong;
  final Color brandSoft;
  final Color onBrand;
  final Color pageBg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color border;
  final Color warnBg;
  final Color warnFg;
  final Color badBg;
  final Color badFg;
  final Color okBg;
  final Color okFg;
  final Color infoBg;
  final Color infoFg;
  final Color checkedBg;
  final Color checkedFg;

  /// `--card-shadow`: dua lapis bayangan halus, BUKAN garis.
  final List<BoxShadow> bayangan;

  static const terang = WarnaTerra(
    brand: Color(0xFF154DEC),
    brandStrong: Color(0xFF0F3FD0),
    brandSoft: Color(0xFFE7ECFB),
    onBrand: Color(0xFFFFFFFF),
    pageBg: Color(0xFFF7F9FB),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFAFBFC),
    ink: Color(0xFF16181D),
    muted: Color(0xFF6B7280),
    faint: Color(0xFF9AA0AB),
    line: Color(0xFFEEF0F3),
    border: Color(0xFFE3E6EB),
    warnBg: Color(0xFFFCF0D9),
    warnFg: Color(0xFF8F5914),
    badBg: Color(0xFFFDECEC),
    badFg: Color(0xFFB3322F),
    okBg: Color(0xFFE6F6EC),
    okFg: Color(0xFF1A7F45),
    infoBg: Color(0xFFEEF3FF),
    infoFg: Color(0xFF274690),
    checkedBg: Color(0xFFE3CEF7),
    checkedFg: Color(0xFF5B1D91),
    bayangan: [
      BoxShadow(color: Color(0x0A101828), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x0D101828), offset: Offset(0, 4), blurRadius: 16),
    ],
  );

  static const gelap = WarnaTerra(
    brand: Color(0xFF7BA0FF),
    brandStrong: Color(0xFF9DB8FF),
    brandSoft: Color(0xFF22304F),
    onBrand: Color(0xFF16181D),
    pageBg: Color(0xFF14161B),
    surface: Color(0xFF1A1D24),
    surface2: Color(0xFF1F2229),
    ink: Color(0xFFE7E9EE),
    muted: Color(0xFFA0A6B0),
    faint: Color(0xFF767C88),
    line: Color(0xFF2A2F3A),
    border: Color(0xFF2F3540),
    warnBg: Color(0xFF33260F),
    warnFg: Color(0xFFE0A54E),
    badBg: Color(0xFF331717),
    badFg: Color(0xFFF08585),
    okBg: Color(0xFF12301F),
    okFg: Color(0xFF5FD08A),
    infoBg: Color(0xFF16203A),
    infoFg: Color(0xFF9DBAFF),
    checkedBg: Color(0xFF2D1A42),
    checkedFg: Color(0xFFCFA6F7),
    bayangan: [
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x73000000), offset: Offset(0, 4), blurRadius: 16),
    ],
  );

  @override
  WarnaTerra copyWith() => this;

  @override
  WarnaTerra lerp(ThemeExtension<WarnaTerra>? other, double t) {
    if (other is! WarnaTerra) return this;
    return t < 0.5 ? this : other;
  }
}

extension WarnaTerraKonteks on BuildContext {
  WarnaTerra get warna => Theme.of(this).extension<WarnaTerra>() ?? WarnaTerra.terang;
}
