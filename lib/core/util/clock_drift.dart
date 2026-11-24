import 'package:flutter/widgets.dart' show Locale;

import '../i18n.dart';

/// How far the phone clock was from the server clock at the last pull.
///
/// The pull stores `server_time` as `<server ISO>|<phone ISO at that moment>`.
/// Positive = the phone runs AHEAD of the server. Null when unknown or
/// unparsable. The comparison is instant-to-instant, so time zones do not
/// matter — only a wrong clock does.
Duration? clockDriftOf(String? meta) {
  if (meta == null) return null;
  final parts = meta.split('|');
  if (parts.length != 2) return null;
  final server = DateTime.tryParse(parts[0]);
  final phone = DateTime.tryParse(parts[1]);
  if (server == null || phone == null) return null;
  return phone.toUtc().difference(server.toUtc());
}

/// Past this the Home page shows a red banner. A few minutes is normal
/// network and processing delay; ten is a clock that was set by hand.
const clockDriftWarn = Duration(minutes: 10);

/// "12 menit lebih cepat" / "2 jam 5 menit terlambat".
String clockDriftText(Duration d) {
  final abs = d.abs();
  final h = abs.inHours;
  final m = abs.inMinutes % 60;
  final l = L10n.current ?? lookupAppLocalizations(const Locale('id'));
  final amount = h == 0 ? l.driftMinutes('$m') : (m == 0 ? l.driftHours('$h') : l.driftHoursMinutes('$h', '$m'));
  return d.isNegative ? l.driftSlow(amount) : l.driftFast(amount);
}
