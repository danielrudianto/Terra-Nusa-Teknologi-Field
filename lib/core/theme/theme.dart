import 'package:flutter/material.dart';

import 'appearance.dart';
import 'color_tokens.dart';
import 'dimens.dart';

/// ThemeData from the TerraBot tokens. One function for light and dark,
/// so the two do not differ in shape — only in color. [accent] (Pengaturan →
/// Tampilan) swaps the brand trio and nothing else.
ThemeData buildTheme(Brightness light, {AccentOption? accent}) {
  var w = light == Brightness.light ? TerraColors.light : TerraColors.dark;
  if (accent != null) {
    w = light == Brightness.light
        ? w.withAccent(brand: accent.lightBrand, brandStrong: accent.lightStrong, brandSoft: accent.lightSoft)
        : w.withAccent(brand: accent.darkBrand, brandStrong: accent.darkStrong, brandSoft: accent.darkSoft);
  }
  final scheme = ColorScheme(
    brightness: light,
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

  final base = ThemeData(
    useMaterial3: true,
    brightness: light,
    colorScheme: scheme,
    fontFamily: 'Montserrat',
    scaffoldBackgroundColor: w.pageBg,
    extensions: [w],
  );

  return base.copyWith(
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
        minimumSize: const Size(64, Dimens.minTouch),
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dimens.radiusBanner)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, Dimens.minTouch),
        side: BorderSide(color: w.border),
        textStyle: const TextStyle(fontFamily: 'Montserrat', fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dimens.radiusBanner)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: w.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusBanner),
        borderSide: BorderSide(color: w.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusBanner),
        borderSide: BorderSide(color: w.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusBanner),
        borderSide: BorderSide(color: w.brand, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      // NO helperText anywhere: small hint text below a field is not
      // legible on a phone. Explanations go into TerraBanner.
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: w.surface,
      indicatorColor: w.brandSoft,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontFamily: 'Montserrat', fontSize: 12, fontWeight: FontWeight.w600, color: w.ink),
      ),
    ),
    // Dialog titles in the same face as the app bar title ("Cor PP.A1"),
    // not Material's large thin headline.
    dialogTheme: DialogThemeData(
      backgroundColor: w.surface,
      // Material's 40 px side margin leaves a narrow column on a phone, where
      // banners wrap into tall, broken-looking blocks.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titleTextStyle: TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w800,
        fontSize: 20,
        letterSpacing: -0.2,
        color: w.ink,
      ),
      contentTextStyle: TextStyle(fontFamily: 'Montserrat', fontSize: 15, color: w.ink),
    ),
    dividerTheme: DividerThemeData(color: w.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Dimens.radiusBanner)),
    ),
  );
}
