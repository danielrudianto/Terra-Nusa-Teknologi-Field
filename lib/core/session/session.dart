import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The logged-in user — from the `POST /auth/` response.
class AppUser {
  const AppUser({required this.id, required this.name, required this.email, required this.level});

  final int id;
  final String name;
  final String email;
  final int level;

  factory AppUser.fromJson(Map<String, Object?> j) => AppUser(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        level: (j['authenticationLevel'] as num?)?.toInt() ?? 1,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'email': email, 'authenticationLevel': level};

  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((k) => k.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return (words.first[0] + (words.length > 1 ? words.last[0] : '')).toUpperCase();
  }
}

/// Permission map from `GET /permissions/me` — shown as is.
///
/// Hiding a menu is NOT security; the server still checks every push.
/// This only keeps the foreman from seeing buttons that will certainly be rejected.
class PermissionMap {
  const PermissionMap({required this.level, required this.departments, required this.permissions, required this.readOnly});

  final int level;
  final List<String> departments;
  final Map<String, Map<String, bool>> permissions;
  final bool readOnly;

  static const empty = PermissionMap(level: 1, departments: [], permissions: {}, readOnly: false);

  bool allows(String module, String action) => permissions[module]?[action] ?? false;

  factory PermissionMap.fromJson(Map<String, Object?> j) {
    final raw = (j['permissions'] as Map?) ?? const {};
    return PermissionMap(
      level: (j['level'] as num?)?.toInt() ?? 1,
      departments: [for (final d in (j['departments'] as List?) ?? const []) d.toString()],
      permissions: {
        for (final e in raw.entries)
          e.key.toString(): {
            for (final a in ((e.value as Map?) ?? const {}).entries) a.key.toString(): a.value == true,
          },
      },
      readOnly: j['readOnly'] == true,
    );
  }

  Map<String, Object?> toJson() =>
      {'level': level, 'departments': departments, 'permissions': permissions, 'readOnly': readOnly};
}

/// Secure storage: tokens, user, and the last permissions.
///
/// The LAST permissions are stored so the phone still knows which menus to show
/// when opened without signal — after the first login, the app must be usable
/// all day on site without a network.
class SessionStore {
  SessionStore(this.storage);

  final FlutterSecureStorage storage;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'user';
  static const _permissionsKey = 'permissions';
  static const _expiredKey = 'session_expired';

  Future<String?> accessToken() => storage.read(key: _accessKey);
  Future<String?> refreshToken() => storage.read(key: _refreshKey);

  Future<void> writeTokens(String access, String refresh) async {
    await storage.write(key: _accessKey, value: access);
    await storage.write(key: _refreshKey, value: refresh);
    await storage.delete(key: _expiredKey);
  }

  Future<void> writeUser(AppUser p) => storage.write(key: _userKey, value: jsonEncode(p.toJson()));
  Future<void> writePermissions(PermissionMap i) => storage.write(key: _permissionsKey, value: jsonEncode(i.toJson()));

  Future<AppUser?> user() async {
    final t = await storage.read(key: _userKey);
    if (t == null) return null;
    return AppUser.fromJson((jsonDecode(t) as Map).cast<String, Object?>());
  }

  Future<PermissionMap> permissions() async {
    final t = await storage.read(key: _permissionsKey);
    if (t == null) return PermissionMap.empty;
    return PermissionMap.fromJson((jsonDecode(t) as Map).cast<String, Object?>());
  }

  /// The server rejected the refresh token. Documents on the phone are NOT deleted; all
  /// that is asked is to log in again so the queue can be pushed.
  Future<void> markSessionExpired() => storage.write(key: _expiredKey, value: '1');
  Future<bool> sessionExpired() async => (await storage.read(key: _expiredKey)) == '1';

  /// Logout: tokens and permissions are discarded. The last user is KEPT so that
  /// their queue is still recognized if they log in again.
  Future<void> logout() async {
    await storage.delete(key: _accessKey);
    await storage.delete(key: _refreshKey);
    await storage.delete(key: _permissionsKey);
    await storage.delete(key: _expiredKey);
  }

  Future<void> forgetUser() => storage.delete(key: _userKey);
}
