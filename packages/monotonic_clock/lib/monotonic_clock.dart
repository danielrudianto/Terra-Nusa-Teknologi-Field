/// Android monotonic clock: milliseconds since the phone booted + boot count.
///
/// WHY A PLUGIN, NOT A MethodChannel IN MainActivity
///
/// The push queue also runs in the background (workmanager) — a Flutter engine
/// SEPARATE from the screen, with no MainActivity. A channel registered in
/// MainActivity does not exist there, and every push from the background would
/// arrive without a monotonic clock: the server could not verify the phone's clock.
/// A plugin is registered automatically in ALL engines, including the background one.
library;

import 'package:flutter/services.dart';

class MonotonicReading {
  const MonotonicReading({required this.elapsedMs, required this.bootCount});

  /// `SystemClock.elapsedRealtime()` — cannot be changed through Settings.
  final int elapsedMs;

  /// `Settings.Global.BOOT_COUNT`; null if unavailable on that phone.
  final int? bootCount;
}

class MonotonicClock {
  static const MethodChannel _channel = MethodChannel('id.co.alphakonstruksi/monotonic_clock');

  /// Null if the platform does not support it (e.g. when testing on desktop).
  static Future<MonotonicReading?> read() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('read');
      if (result == null) return null;
      final elapsed = result['elapsedMs'];
      final boot = result['bootCount'];
      if (elapsed is! int) return null;
      return MonotonicReading(elapsedMs: elapsed, bootCount: boot is int ? boot : null);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
