import 'package:monotonic_clock/monotonic_clock.dart';

import '../util/format.dart';

/// A single point in time from the phone: wall clock + monotonic clock.
///
/// The wall clock can be shifted by the foreman in Settings; the monotonic clock cannot.
/// The server compares the two against the monotonic clock at PUSH time to
/// work out when this event actually happened (`jam_terpercaya`).
class DeviceTimestamp {
  const DeviceTimestamp({required this.at, this.elapsedMs, this.bootCount});

  final DateTime at;
  final int? elapsedMs;
  final int? bootCount;

  static Future<DeviceTimestamp> now() async {
    final m = await MonotonicClock.read();
    return DeviceTimestamp(at: DateTime.now(), elapsedMs: m?.elapsedMs, bootCount: m?.bootCount);
  }

  /// The `at/elapsedMs/bootCount/timeEdited` fields on an attendance event.
  Map<String, Object?> toEvent({bool edited = false}) => {
        'at': isoWithOffset(at),
        'elapsedMs': edited ? null : elapsedMs,
        'bootCount': edited ? null : bootCount,
        'timeEdited': edited,
      };

  Map<String, Object?> toJson() => {'at': isoWithOffset(at), 'elapsedMs': elapsedMs, 'bootCount': bootCount};

  static DeviceTimestamp? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = DateTime.tryParse('${j['at']}');
    if (s == null) return null;
    return DeviceTimestamp(at: s, elapsedMs: toIntOrNull(j['elapsedMs']), bootCount: toIntOrNull(j['bootCount']));
  }
}
