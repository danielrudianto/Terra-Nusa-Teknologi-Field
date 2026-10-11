import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../util/format.dart';

const _storageKey = 'device_id';

/// Identifier of this phone — created ONCE when the app is first opened, sent
/// in the `X-Device-Id` header on every request.
///
/// The server uses it for two things: blocking lost phones, and recognizing
/// that an old refresh token showing up again comes from the same phone whose
/// response got lost on the way (not a thief).
Future<String> loadDeviceId(FlutterSecureStorage storage) async {
  final existing = await storage.read(key: _storageKey);
  if (existing != null && existing.isNotEmpty) return existing;
  final fresh = newUuid();
  await storage.write(key: _storageKey, value: fresh);
  return fresh;
}
