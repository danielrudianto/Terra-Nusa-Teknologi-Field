import 'package:flutter/services.dart';

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
  List<String> get steps => switch (manufacturer) {
        'xiaomi' || 'redmi' || 'poco' => const [
            'Mulai otomatis (Autostart): NYALAKAN untuk TerraBot Field.',
            'Penghemat baterai: pilih "Tanpa batasan" (No restrictions).',
          ],
        'oppo' || 'realme' || 'oneplus' => const [
            'Mulai otomatis / Izinkan auto-launch: NYALAKAN untuk TerraBot Field.',
            'Penggunaan baterai: izinkan "Aktivitas latar belakang" dan "Mulai otomatis".',
          ],
        'vivo' || 'iqoo' => const [
            'Auto-start / Latar belakang: IZINKAN untuk TerraBot Field.',
            'Baterai → Konsumsi daya latar tinggi: IZINKAN.',
          ],
        'huawei' || 'honor' => const [
            'Peluncuran aplikasi: matikan "Kelola otomatis", lalu nyalakan Mulai otomatis, Mulai sekunder, dan Jalankan di latar.',
          ],
        'samsung' => const [
            'Baterai: pilih "Tidak dibatasi" (Unrestricted).',
            'Pastikan TerraBot Field TIDAK ada di daftar "Aplikasi tidur" / "Aplikasi tidur nyenyak".',
          ],
        _ => const ['Baterai: pilih "Tanpa batasan" / "Tidak dioptimalkan" untuk TerraBot Field.'],
      };
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
