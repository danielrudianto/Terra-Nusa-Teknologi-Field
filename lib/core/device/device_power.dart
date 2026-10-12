import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../i18n.dart';

/// Battery saving / auto-start state of this phone (see MainActivity.kt).
class PowerStatus {
  const PowerStatus({required this.manufacturer, required this.unrestricted});

  /// Lower case, e.g. `xiaomi`, `oppo`, `vivo`, `samsung`.
  final String manufacturer;

  /// Battery optimisation is OFF for this app ("Tanpa batasan").
  final bool unrestricted;

  /// Brands that also have their own auto-start switch, off by default.
  bool get hasAutostart => const ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'oneplus', 'vivo', 'iqoo', 'huawei', 'honor']
      .contains(manufacturer);

  /// What to switch on, in the words of that brand's settings.
  ///
  /// These name the labels the PHONE shows, so they follow the app language
  /// the person picked — someone reading the app in English is reading an
  /// English phone.
  List<String> steps(BuildContext context) {
    final l = t(context);
    return switch (manufacturer) {
      'xiaomi' || 'redmi' || 'poco' => [l.powerXiaomi1, l.powerXiaomi2],
      'oppo' || 'realme' || 'oneplus' => [l.powerOppo1, l.powerOppo2],
      'vivo' || 'iqoo' => [l.powerVivo1, l.powerVivo2],
      'huawei' || 'honor' => [l.powerHuawei1],
      'samsung' => [l.powerSamsung1, l.powerSamsung2],
      _ => [l.powerGeneric],
    };
  }
}

abstract final class DevicePower {
  static const _channel = MethodChannel('terrabot/device_power');

  /// Null when it cannot be read (not Android, tests).
  static Future<PowerStatus?> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('status');
      if (m == null) return null;
      return PowerStatus(
        manufacturer: '${m['manufacturer'] ?? ''}',
        unrestricted: m['ignoringBatteryOptimizations'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// The app's info page (Baterai lives there on most phones).
  static Future<bool> openAppSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAppSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The brand's auto-start list; false when unknown (then use app settings).
  static Future<bool> openAutostart() async {
    try {
      return await _channel.invokeMethod<bool>('openAutostart') ?? false;
    } catch (_) {
      return false;
    }
  }
}
