import 'package:jam_monoton/jam_monoton.dart';

import '../util/format.dart';

/// Satu titik waktu dari HP: jam dinding + jam monoton.
///
/// Jam dinding dapat digeser mandor di Pengaturan; jam monoton tidak.
/// Server membandingkan keduanya dengan jam monoton saat KIRIM untuk
/// menghitung kapan sebenarnya kejadian ini terjadi (`jam_terpercaya`).
class StempelWaktu {
  const StempelWaktu({required this.saat, this.elapsedMs, this.bootCount});

  final DateTime saat;
  final int? elapsedMs;
  final int? bootCount;

  static Future<StempelWaktu> sekarang() async {
    final m = await JamMonoton.ambil();
    return StempelWaktu(saat: DateTime.now(), elapsedMs: m?.elapsedMs, bootCount: m?.bootCount);
  }

  /// Bidang `at/elapsedMs/bootCount/timeEdited` pada kejadian absen.
  Map<String, Object?> keKejadian({bool diedit = false}) => {
        'at': isoBerzona(saat),
        'elapsedMs': diedit ? null : elapsedMs,
        'bootCount': diedit ? null : bootCount,
        'timeEdited': diedit,
      };

  Map<String, Object?> keJson() => {'saat': isoBerzona(saat), 'elapsedMs': elapsedMs, 'bootCount': bootCount};

  static StempelWaktu? dariJson(Object? j) {
    if (j is! Map) return null;
    final s = DateTime.tryParse('${j['saat']}');
    if (s == null) return null;
    return StempelWaktu(saat: s, elapsedMs: keInt(j['elapsedMs']), bootCount: keInt(j['bootCount']));
  }
}
