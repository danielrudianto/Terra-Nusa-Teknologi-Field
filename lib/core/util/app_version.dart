import 'dart:convert';

/// `[major, minor, patch, build]` — ALWAYS four numbers, zero-filled.
///
/// 'v1.0.1+14' → [1, 0, 1, 14] · '0.2' → [0, 2, 0, 0] · unreadable →
/// [0, 0, 0, 0].
///
/// THE BUILD NUMBER COUNTS, as of 14 Oct 2026. It used to be dropped along
/// with everything after '+', so 1.0.0+10 and 1.0.0+13 read the SAME and a
/// release that only raised the build number could not be forced.
///
/// MUST STAY IDENTICAL to `urai_versi` on the server, down to the
/// zero-filling. The server answers 426 by its own reading, and the phone
/// decides by this one whether to show the update screen — disagree, and the
/// phone that the server refuses hides the screen that explains why, leaving
/// the crew with a sync that fails in silence.
List<int> parseVersion(String? text) {
  final trimmed = (text ?? '').trim().replaceFirst(RegExp('^[vV]'), '');
  final plus = trimmed.indexOf('+');
  final core = (plus < 0 ? trimmed : trimmed.substring(0, plus)).split('-').first;
  final buildText = plus < 0 ? '' : trimmed.substring(plus + 1).split('-').first;
  final parts = [
    for (final p in core.split('.')) int.tryParse(p.replaceAll(RegExp(r'\D'), '')) ?? 0,
  ];
  while (parts.length < 3) {
    parts.add(0);
  }
  final digits = buildText.replaceAll(RegExp(r'\D'), '');
  return [parts[0], parts[1], parts[2], int.tryParse(digits) ?? 0];
}

/// Negative when [a] is older than [b], 0 when equal, positive when newer.
/// Compared as numbers: 0.9 is older than 0.10.
int compareVersions(String? a, String? b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  for (var i = 0; i < x.length; i++) {
    final d = x[i] - y[i];
    if (d != 0) return d;
  }
  return 0;
}

/// The server no longer serves this app version (APP_KEDALUWARSA, HTTP 426).
class AppOutdated {
  const AppOutdated({required this.minVersion, this.downloadUrl});

  final String minVersion;
  final String? downloadUrl;

  /// Still true for [current]? False once the phone runs a new enough
  /// version, so the block lifts right after updating, before any sync.
  bool appliesTo(String current) => compareVersions(current, minVersion) < 0;

  factory AppOutdated.fromContext(Map<String, Object?>? context) => AppOutdated(
        minVersion: '${context?['minVersion'] ?? ''}',
        downloadUrl: (context?['downloadUrl'] as String?)?.trim().isEmpty ?? true ? null : context!['downloadUrl'] as String,
      );

  String encode() => jsonEncode({'minVersion': minVersion, 'downloadUrl': downloadUrl});

  static AppOutdated? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return AppOutdated.fromContext((jsonDecode(text) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }
}
