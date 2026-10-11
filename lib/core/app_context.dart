import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config/env.dart';
import 'db/app_database.dart';
import 'network/api_client.dart';
import 'device/device_id.dart';
import 'session/session.dart';
import 'sync/sync_engine.dart';

/// Everything needed to talk to the server and the local database.
///
/// Created in TWO places: `main()` for the screen, and the background worker for
/// periodic sync. Both must assemble it the SAME way — that is why the
/// assembly lives in this one function instead of being written twice.
class AppContext {
  AppContext._({
    required this.db,
    required this.session,
    required this.api,
    required this.engine,
    required this.deviceId,
  });

  final AppDatabase db;
  final SessionStore session;
  final ApiClient api;
  final SyncEngine engine;
  final String deviceId;

  static Future<AppContext> open() async {
    await Env.loadVersion();
    const storage = FlutterSecureStorage();
    final id = await loadDeviceId(storage);
    final db = AppDatabase();
    final session = SessionStore(storage);
    final api = ApiClient(db: db, session: session, deviceId: id);
    final engine = SyncEngine(db: db, api: api, session: session);
    return AppContext._(db: db, session: session, api: api, engine: engine, deviceId: id);
  }

  Future<void> close() => db.close();
}
