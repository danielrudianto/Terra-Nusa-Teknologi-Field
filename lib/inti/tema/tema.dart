import 'package:flutter/material.dart';

import 'token_warna.dart';
import 'ukuran.dart';

/// ThemeData dari token TerraBot. Satu fungsi untuk terang dan gelap,
/// supaya keduanya tidak berbeda bentuk — hanya warnanya.
ThemeData buatTema(Brightness terang) {
  final w = terang == Brightness.light ? WarnaTerra.terang : WarnaTerra.gelap;
  final skema = ColorScheme(
    brightness: terang,
    primary: w.brand,
    onPrimary: w.onBrand,
    primaryContainer: w.brandSoft,
    onPrimaryContainer: w.brandStrong,
    secondary: w.brandStrong,
    onSecondary: w.onBrand,
    error: w.badFg,
    onError: w.surface,
    surface: w.surface,
    onSurface: w.ink,
    onSurfaceVariant: w.muted,
    outline: w.border,
    outlineVariant: w.line,
  );

  final dasar = ThemeData(
    useMaterial3: true,
    brightness: terang,
    colorScheme: skema,
    fontFamily: 'Montserrat',
    scaffoldBackgroundColor: w.pageBg,
    extensions: [w],
  );

  return dasar.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: w.surface,
      foregroundColor: w.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w800,
        fontSize: 18,
        letterSpacing: -0.2,
        color: w.ink,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, Ukuran.sentuhMinimum),
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ukuran.radiusBanner)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, Ukuran.sentuhMinimum),
        side: BorderSide(color: w.border),
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ukuran.radiusBanner)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: w.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ukuran.radiusBanner),
        borderSide: BorderSide(color: w.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ukuran.radiusBanner),
        borderSide: BorderSide(color: w.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ukuran.radiusBanner),
        borderSide: BorderSide(color: w.brand, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // TANPA helperText di mana pun: hint kecil di bawah field tidak
      // terbaca di HP. Penjelasan masuk BannerTerra.
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: w.surface,
      indicatorColor: w.brandSoft,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w600, color: w.ink),
      ),
    ),
    dividerTheme: DividerThemeData(color: w.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Ukuran.radiusBanner)),
    ),
  );
}
