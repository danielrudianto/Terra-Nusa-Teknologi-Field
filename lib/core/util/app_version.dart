import 'dart:convert';

/// '0.2.1' / '0.2.1+7' / 'v0.2' → [0, 2, 1] / [0, 2, 1] / [0, 2]. Unreadable = [0].
///
/// The same reading as `urai_versi` on the server: the build number after
/// '+' is ignored and trailing zeros do not count, so 0.2 == 0.2.0.
List<int> parseVersion(String? text) {
  final core = (text ?? '').trim().replaceFirst(RegExp('^[vV]'), '').split('+').first.split('-').first;
  final parts = [
    for (final p in core.split('.')) int.tryParse(p.replaceAll(RegExp(r'\D'), '')) ?? 0,
  ];
  while (parts.length > 1 && parts.last == 0) {
    parts.removeLast();
  }
  return parts.isEmpty ? [0] : parts;
}

/// Negative when [a] is older than [b], 0 when equal, positive when newer.
/// Compared as numbers: 0.9 is older than 0.10.
int compareVersions(String? a, String? b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
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
