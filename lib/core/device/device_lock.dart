import 'dart:convert';

/// "HP ini sudah digantikan": the account was used to sign in on another
/// phone (one account, one phone).
///
/// This phone is NOT signed out. Signing it out would strand whatever it has
/// not managed to send — and the phone that gets locked is often the one with
/// the worst signal, holding a whole day of logs. So it keeps pulling and
/// keeps pushing its queue; what it loses is the right to start new work,
/// and only after [until].
///
/// The way back needs no admin: sign in again ON THIS PHONE.
class DeviceLock {
  const DeviceLock({required this.since, required this.until, this.byName});

  final DateTime since;

  /// Until when this phone may still record NEW work (the grace window the
  /// server grants, so a phone that was offline when it got locked does not
  /// lose the day it kept working through).
  final DateTime until;

  /// The phone that took over, when the server knows its name.
  final String? byName;

  bool get graceOver => DateTime.now().isAfter(until);

  /// Reads the `device` block of a pull answer. Null = not locked.
  static DeviceLock? fromPull(Object? raw) {
    if (raw is! Map) return null;
    if (raw['locked'] != true) return null;
    final since = DateTime.tryParse('${raw['lockedAt']}');
    final until = DateTime.tryParse('${raw['lockedUntil']}');
    if (since == null || until == null) return null;
    return DeviceLock(since: since, until: until, byName: raw['lockedByName']?.toString());
  }

  String encode() => jsonEncode({
        'since': since.toIso8601String(),
        'until': until.toIso8601String(),
        if (byName != null) 'byName': byName,
      });

  static DeviceLock? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, Object?>;
      final since = DateTime.tryParse('${m['since']}');
      final until = DateTime.tryParse('${m['until']}');
      if (since == null || until == null) return null;
      return DeviceLock(since: since, until: until, byName: m['byName']?.toString());
    } catch (_) {
      return null;
    }
  }
}
