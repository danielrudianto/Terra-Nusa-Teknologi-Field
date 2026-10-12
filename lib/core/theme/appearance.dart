import 'dart:convert';

import 'package:flutter/material.dart';

/// How the app looks, chosen in Pengaturan → Tampilan: theme mode, accent
/// color, text size. Stored as one JSON string under the meta key
/// [appearanceKey], so it survives logout and applies before login too.
const appearanceKey = 'appearance';

/// One selectable accent: the brand trio for light and for dark.
///
/// CURATED, not a free color picker: every pair below was chosen so that
/// white text on the light brand, and the dark brand on the dark page
/// background, stay readable. A free picker lets someone choose a yellow
/// that makes every button unreadable in the sun — the opposite of what a
/// field app needs.
class AccentOption {
  const AccentOption({
    required this.id,
    required this.label,
    required this.lightBrand,
    required this.lightStrong,
    required this.lightSoft,
    required this.darkBrand,
    required this.darkStrong,
    required this.darkSoft,
  });

  final String id;
  final String label;
  final Color lightBrand;
  final Color lightStrong;
  final Color lightSoft;
  final Color darkBrand;
  final Color darkStrong;
  final Color darkSoft;
}

/// First entry = the TerraBot default (same values as TerraColors).
const accentOptions = <AccentOption>[
  AccentOption(
    id: 'biru',
    label: 'Biru TerraBot',
    lightBrand: Color(0xFF154DEC),
    lightStrong: Color(0xFF0F3FD0),
    lightSoft: Color(0xFFE7ECFB),
    darkBrand: Color(0xFF7BA0FF),
    darkStrong: Color(0xFF9DB8FF),
    darkSoft: Color(0xFF22304F),
  ),
  AccentOption(
    id: 'jingga',
    label: 'Jingga AKN',
    lightBrand: Color(0xFFC2410C),
    lightStrong: Color(0xFF9A3412),
    lightSoft: Color(0xFFFBE8DD),
    darkBrand: Color(0xFFFB923C),
    darkStrong: Color(0xFFFDBA74),
    darkSoft: Color(0xFF3B2412),
  ),
  AccentOption(
    id: 'teal',
    label: 'Teal',
    lightBrand: Color(0xFF0F766E),
    lightStrong: Color(0xFF115E59),
    lightSoft: Color(0xFFD9F0EE),
    darkBrand: Color(0xFF2DD4BF),
    darkStrong: Color(0xFF5EEAD4),
    darkSoft: Color(0xFF11312E),
  ),
  AccentOption(
    id: 'ungu',
    label: 'Ungu',
    lightBrand: Color(0xFF6D28D9),
    lightStrong: Color(0xFF5B21B6),
    lightSoft: Color(0xFFEDE4FB),
    darkBrand: Color(0xFFA78BFA),
    darkStrong: Color(0xFFC4B5FD),
    darkSoft: Color(0xFF2B2144),
  ),
];

AccentOption accentById(String? id) =>
    accentOptions.firstWhere((a) => a.id == id, orElse: () => accentOptions.first);

/// Text sizes on offer. The base theme is already sized for gloves and
/// sunlight, so "Normal" is 1.0 and the others only go UP — field users ask
/// for bigger, never smaller.
const textScaleOptions = <(String, double)>[
  ('Normal', 1.0),
  ('Besar', 1.15),
  ('Sangat besar', 1.3),
];

/// Languages on offer. Indonesian is the language the app was written in;
/// the other two exist because the work gets shown to people who do not read
/// it — an owner, a client, an investor.
const languageOptions = <String>['id', 'en', 'zh'];

@immutable
class Appearance {
  const Appearance({
    this.mode = ThemeMode.system,
    this.accentId = 'biru',
    this.textScale = 1.0,
    this.languageCode,
  });

  final ThemeMode mode;
  final String accentId;
  final double textScale;

  /// null = follow the phone. A phone set to a language the app does not
  /// speak falls back to Indonesian, which is what the site speaks.
  final String? languageCode;

  Locale? get locale => languageCode == null ? null : Locale(languageCode!);

  AccentOption get accent => accentById(accentId);

  Appearance copyWith({ThemeMode? mode, String? accentId, double? textScale}) => Appearance(
        mode: mode ?? this.mode,
        accentId: accentId ?? this.accentId,
        textScale: textScale ?? this.textScale,
        languageCode: languageCode,
      );

  /// Its own method, not a `copyWith` argument: null here MEANS "follow the
  /// phone", and `copyWith(languageCode: null)` could not say that.
  Appearance withLanguage(String? code) => Appearance(
        mode: mode,
        accentId: accentId,
        textScale: textScale,
        languageCode: code,
      );

  String encode() => jsonEncode({
        'mode': mode.name,
        'accent': accentId,
        'scale': textScale,
        if (languageCode != null) 'lang': languageCode,
      });

  /// Defaults on anything missing or unparsable: a broken saved value must
  /// never keep the app from starting.
  static Appearance decode(String? text) {
    if (text == null || text.isEmpty) return const Appearance();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const Appearance();
      final mode = ThemeMode.values.asNameMap()[j['mode']] ?? ThemeMode.system;
      final accent = accentById(j['accent'] is String ? j['accent'] as String : null).id;
      final rawScale = j['scale'];
      var scale = rawScale is num ? rawScale.toDouble() : 1.0;
      if (!textScaleOptions.any((o) => o.$2 == scale)) scale = 1.0;
      final lang = j['lang'];
      return Appearance(
        mode: mode,
        accentId: accent,
        textScale: scale,
        languageCode: lang is String && languageOptions.contains(lang) ? lang : null,
      );
    } catch (_) {
      return const Appearance();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.mode == mode &&
      other.accentId == accentId &&
      other.textScale == textScale &&
      other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(mode, accentId, textScale, languageCode);
}
