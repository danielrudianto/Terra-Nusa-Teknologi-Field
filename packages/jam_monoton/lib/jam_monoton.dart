/// Jam monoton Android: milidetik sejak HP menyala + jumlah boot.
///
/// KENAPA PLUGIN, BUKAN MethodChannel DI MainActivity
///
/// Antrean kirim juga berjalan di latar (workmanager) — mesin Flutter yang
/// TERPISAH dari layar, tanpa MainActivity. Saluran yang didaftarkan di
/// MainActivity tidak ada di sana, dan setiap kiriman dari latar akan
/// tiba tanpa jam monoton: server tidak dapat membuktikan jam HP-nya.
/// Plugin didaftarkan otomatis di SEMUA mesin, termasuk mesin latar.
library;

import 'package:flutter/services.dart';

class JamMonotonNilai {
  const JamMonotonNilai({required this.elapsedMs, required this.bootCount});

  /// `SystemClock.elapsedRealtime()` — tidak dapat diubah lewat Pengaturan.
  final int elapsedMs;

  /// `Settings.Global.BOOT_COUNT`; null bila tidak tersedia di HP itu.
  final int? bootCount;
}

class JamMonoton {
  static const MethodChannel _saluran = MethodChannel('id.co.alphakonstruksi/jam_monoton');

  /// Null bila platform tidak mendukung (mis. saat uji di desktop).
  static Future<JamMonotonNilai?> ambil() async {
    try {
      final hasil = await _saluran.invokeMapMethod<String, Object?>('ambil');
      if (hasil == null) return null;
      final elapsed = hasil['elapsedMs'];
      final boot = hasil['bootCount'];
      if (elapsed is! int) return null;
      return JamMonotonNilai(elapsedMs: elapsed, bootCount: boot is int ? boot : null);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
