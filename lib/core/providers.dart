import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/app_database.dart';
import 'network/api_client.dart';
import 'network/api_error.dart';
import 'app_context.dart';
import 'session/session.dart';
import 'sync/sync_engine.dart';
import 'sync/background_sync.dart';
import 'config/env.dart';
import 'device/notifications.dart';
import 'theme/appearance.dart';
import 'util/app_version.dart';
import 'util/clock_drift.dart';
import 'util/format.dart';
import '../features/workers/worker.dart';
import 'device/device_lock.dart';

export '../features/workers/worker.dart';
export 'util/app_version.dart' show AppOutdated;

/// Filled in `main()` via `overrides`. All other providers derive from it.
final appContextProvider = Provider<AppContext>((ref) => throw UnimplementedError('konteksProvider belum diisi'));

final dbProvider = Provider<AppDatabase>((ref) => ref.watch(appContextProvider).db);
final apiProvider = Provider<ApiClient>((ref) => ref.watch(appContextProvider).api);
final syncEngineProvider = Provider<SyncEngine>((ref) => ref.watch(appContextProvider).engine);

// ===========================================================================
// Session
// ===========================================================================

class SessionState {
  const SessionState({this.user, this.permissions = PermissionMap.empty, this.sessionExpired = false});

  final AppUser? user;
  final PermissionMap permissions;

  /// Refresh token rejected: data on the phone stays, but the user must log in again
  /// before the queue can be pushed.
  final bool sessionExpired;

  bool get isLoggedIn => user != null && !sessionExpired;
  bool allows(String module, String action) => permissions.allows(module, action);
}

class SessionNotifier extends AsyncNotifier<SessionState> {
  SessionStore get _save => ref.read(appContextProvider).session;

  @override
  Future<SessionState> build() async {
    final user = await _save.user();
    final token = await _save.accessToken();
    final expiresAt = await _save.sessionExpired();
    // No token and not because the server rejected it = genuinely logged out.
    if (user == null || (token == null && !expiresAt)) return const SessionState();
    return SessionState(user: user, permissions: await _save.permissions(), sessionExpired: expiresAt);
  }

  Future<void> login(String email, String password, {bool moveDevice = false}) async {
    final api = ref.read(apiProvider);
    final (user, access, refresh) = await api.login(email, password, moveDevice: moveDevice);
    final previous = await _save.user();
    if (previous != null && previous.id != user.id) {
      await ref.read(dbProvider).switchUser();
    }
    await _save.writeTokens(access, refresh);
    await _save.writeUser(user);
    var permissions = PermissionMap.empty;
    try {
      permissions = await api.permissions();
      await _save.writePermissions(permissions);
    } on ApiError {
      permissions = await _save.permissions();
    }
    state = AsyncData(SessionState(user: user, permissions: permissions));
    unawaited(ref.read(syncProvider.notifier).run());
  }

  /// Called by ApiClient when the refresh token is rejected.
  void markExpired() {
    final now = state.value;
    if (now == null || now.user == null) return;
    state = AsyncData(SessionState(user: now.user, permissions: now.permissions, sessionExpired: true));
  }

  /// Reload permissions from the server (e.g. after an admin adds a module).
  Future<void> reloadPermissions() async {
    final now = state.value;
    if (now == null || !now.isLoggedIn) return;
    try {
      final permissions = await ref.read(apiProvider).permissions();
      await _save.writePermissions(permissions);
      state = AsyncData(SessionState(user: now.user, permissions: permissions));
    } on ApiError {
      // no signal: the last known permissions remain in use
    }
  }

  Future<void> logout() async {
    await ref.read(apiProvider).logout();
    await _save.logout();
    state = const AsyncData(SessionState());
  }
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

/// Active user — null if never logged in.
final userProvider = Provider<AppUser?>((ref) => ref.watch(sessionProvider).value?.user);

/// The project this user works on (Pengaturan → Proyek saya).
///
/// An engineer stays on one site for months, so the app opens on it:
/// attendance and new workers start with it, the casting list puts it on
/// top, the worker list is filtered to it. Any of them can still be changed
/// on the spot. Kept on the phone, per user; null = not chosen.
class MyProjectNotifier extends AsyncNotifier<int?> {
  String? get _key {
    final u = ref.read(userProvider);
    return u == null ? null : 'myProject:${u.id}';
  }

  @override
  Future<int?> build() async {
    ref.watch(userProvider);
    final key = _key;
    if (key == null) return null;
    return int.tryParse(await ref.read(dbProvider).readMeta(key) ?? '');
  }

  Future<void> choose(int? projectId) async {
    final key = _key;
    if (key == null) return;
    await ref.read(dbProvider).writeMeta(key, projectId?.toString());
    state = AsyncData(projectId);
  }
}

final myProjectProvider = AsyncNotifierProvider<MyProjectNotifier, int?>(MyProjectNotifier.new);

/// The chosen project's record, if it is still on the phone.
final myProjectRecordProvider = Provider<Map<String, Object?>?>((ref) {
  final id = ref.watch(myProjectProvider).value;
  if (id == null) return null;
  for (final p in ref.watch(projectsProvider).value ?? const <Map<String, Object?>>[]) {
    if ('${p['id']}' == '$id') return p;
  }
  return null;
});

// ===========================================================================
// Sync
// ===========================================================================

class SyncState {
  const SyncState({this.running = false, this.last, this.lastRunAt});

  final bool running;
  final SyncResult? last;
  final DateTime? lastRunAt;
}

class SyncNotifier extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  /// Push + pull now. Safe to call repeatedly: one that is already
  /// running is not duplicated, and the background worker is blocked by the lock.
  Future<SyncResult?> run() async {
    if (state.running) return null;
    state = SyncState(running: true, last: state.last, lastRunAt: state.lastRunAt);
    SyncResult? result;
    try {
      result = await ref.read(syncEngineProvider).run();
      if (result.sessionExpired) ref.read(sessionProvider.notifier).markExpired();
    } finally {
      state = SyncState(last: result ?? state.last, lastRunAt: DateTime.now());
    }
    await _updateUnsentReminder();
    return result;
  }

  /// After saving a document: try to push now; if there is no signal,
  /// the background worker pushes it as soon as signal arrives.
  void afterSave() {
    unawaited(requestImmediateSync().catchError((_) {}));
    unawaited(run());
  }

  /// Point the "not sent for a day" reminder at the oldest change still
  /// waiting, or drop it when everything is out. Called after every run.
  Future<void> _updateUnsentReminder() async {
    final p = ref.read(userProvider);
    if (p == null) return;
    try {
      final oldest = await ref.read(dbProvider).watchOldestPending(p.id).first;
      if (oldest == null) {
        await Notifications.cancelUnsentReminder();
      } else {
        await Notifications.scheduleUnsentReminder(oldest);
      }
    } catch (_) {
      // A reminder must never break a sync.
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

/// Set while the server refuses this app version and the phone still runs
/// it; null otherwise. Drives the full-screen "Perbarui app" page.
final appOutdatedProvider = StreamProvider<AppOutdated?>((ref) {
  return ref.watch(dbProvider).watchMeta(appOutdatedKey).map((text) {
    final o = AppOutdated.decode(text);
    return o != null && o.appliesTo(Env.appVersion) ? o : null;
  });
});

/// How the app looks (Pengaturan → Tampilan); defaults until first saved.
final appearanceProvider = StreamProvider<Appearance>((ref) {
  return ref.watch(dbProvider).watchMeta(appearanceKey).map(Appearance.decode);
});

/// Phone clock vs server clock at the last pull; null = never pulled.
final clockDriftProvider = StreamProvider<Duration?>((ref) {
  return ref.watch(dbProvider).watchMeta('server_time').map(clockDriftOf);
});

/// Satu akun, satu HP: HP ini sudah digantikan HP lain. Null = tidak.
///
/// Diisi oleh setiap pull, jadi HP yang sedang tanpa sinyal baru
/// mengetahuinya begitu ada sinyal — dan sampai saat itu ia tetap boleh
/// mencatat, yang memang disengaja (lihat masa tenggang di server).
final deviceLockProvider = StreamProvider<DeviceLock?>((ref) {
  return ref.watch(dbProvider).watchMeta('device_lock').map(DeviceLock.decode);
});

/// Boleh memulai pekerjaan BARU di HP ini?
///
/// Mengirim sisa antrean tidak pernah ikut dimatikan: yang sudah tercatat
/// harus tetap sampai ke server, apa pun keadaan HP-nya.
final canRecordProvider = Provider<bool>((ref) {
  final lock = ref.watch(deviceLockProvider).value;
  return lock == null || !lock.graceOver;
});

/// When the oldest change still waiting to be sent was made; null = all sent.
final oldestPendingProvider = StreamProvider<DateTime?>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(null);
  return ref.watch(dbProvider).watchOldestPending(p.id);
});

final pendingCountProvider = StreamProvider<int>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).watchPendingCount(p.id);
});

final rejectedCountProvider = StreamProvider<int>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).watchRejectedCount(p.id);
});

final pendingPhotoCountProvider = StreamProvider<int>((ref) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(0);
  return ref.watch(dbProvider).watchPendingPhotoCount(p.id);
});

// ===========================================================================
// Master data & documents
// ===========================================================================

final projectsProvider = StreamProvider<List<Map<String, Object?>>>((ref) {
  return ref.watch(dbProvider).watchMaster('project').map((d) {
    d.sort((a, b) => '${a['code']}'.compareTo('${b['code']}'));
    return d;
  });
});

/// Projects shown in the CASTING LOG: ongoing projects that have casting work.
///
/// Attendance keeps using [projectsProvider] — crews are still checked in on
/// projects that have no pile casting. Hidden here:
///   * projects in retention (`isRetention`): handed over, no field work left;
///   * projects the office switched off (`fieldCastingEnabled = false`), e.g.
///     MCHP, the always-open bucket for one-off small jobs.
///
/// A missing key counts as "shown", so an older server that does not send
/// these fields still lists every project instead of none.
final castingProjectsProvider = Provider<AsyncValue<List<Map<String, Object?>>>>((ref) {
  return ref.watch(projectsProvider).whenData(
        (all) => [for (final p in all) if (isCastingProject(p)) p],
      );
});

/// See [castingProjectsProvider]. Booleans may arrive as `true`/`false` or `1`/`0`.
bool isCastingProject(Map<String, Object?> project) =>
    !isRetentionProject(project) && _flag(project['fieldCastingEnabled'], fallback: true);

/// Handed over and waiting out the retention period: no more field work.
bool isRetentionProject(Map<String, Object?> project) => _flag(project['isRetention'], fallback: false);

bool _flag(Object? v, {required bool fallback}) =>
    v == null ? fallback : (v == true || v == 1 || v == '1' || v == 'true');

/// Documents owned by the active user, per entity, newest on top.
final documentsProvider = StreamProvider.family<List<DocumentRow>, String>((ref, entity) {
  final p = ref.watch(userProvider);
  if (p == null) return Stream.value(const []);
  return ref.watch(dbProvider).watchDocuments(entity, p.id);
});

/// Workers who can be marked for attendance: EVERY worker of the company.
///
/// A union of two sources: those already on the server (master data), and those
/// NEWLY registered or edited on this phone but not yet pushed. Without the
/// latter, a worker registered in the morning at a site with no signal cannot
/// be marked for attendance until the phone finds a signal.
final workersProvider = StreamProvider<List<Worker>>((ref) {
  final db = ref.watch(dbProvider);
  final p = ref.watch(userProvider);
  final masterRecords = db.watchMaster('worker');
  final isLocal = p == null ? Stream.value(const <DocumentRow>[]) : db.watchDocuments('worker', p.id);
  return _combine(masterRecords, isLocal, (fromServer, documents) {
    final result = <String, Worker>{};
    for (final w in fromServer) {
      if (w['isDelete'] == true) continue;
      result['${w['uuid']}'] = Worker(
        uuid: '${w['uuid']}',
        name: '${w['name']}',
        phone: w['phone']?.toString(),
        active: w['isActive'] != false,
        photoUuid: w['facePhotoUuid']?.toString(),
        projectId: toIntOrNull(w['projectID']),
        lastProjectId: toIntOrNull(w['lastProjectID']),
        lastSeenDate: DateTime.tryParse('${w['lastSeenDate']}'),
      );
    }
    for (final d in documents) {
      final body = (jsonDecode(d.body) as Map).cast<String, Object?>();
      // The phone's version is newer than the server's while it is not yet pushed.
      if (result.containsKey(d.uuid) && d.version <= d.syncedVersion) continue;
      if (d.sendStatus == 'rejected') continue;
      final server = result[d.uuid];
      result[d.uuid] = Worker(
        uuid: d.uuid,
        name: '${body['name']}',
        phone: body['phone']?.toString(),
        active: body['isActive'] != false,
        isLocal: server == null,
        photoUuid: body['facePhotoUuid']?.toString(),
        projectId: toIntOrNull(body['projectID']),
        // Only the server knows where a worker was last absent.
        lastProjectId: server?.lastProjectId,
        lastSeenDate: server?.lastSeenDate,
      );
    }
    final items = result.values.where((w) => w.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  });
});

/// Pile points per project, ordered by `sortOrder` then code.
final pilePointsProvider = StreamProvider.family<List<Map<String, Object?>>, int>((ref, projectId) {
  return ref.watch(dbProvider).watchMaster('pile_point').map((all) {
    final d = [for (final t in all) if ('${t['projectID']}' == '$projectId' && t['isDelete'] != true) t];
    d.sort((a, b) {
      final s = ((a['sortOrder'] as num?) ?? 0).compareTo((b['sortOrder'] as num?) ?? 0);
      return s != 0 ? s : '${a['code']}'.compareTo('${b['code']}');
    });
    return d;
  });
});

/// Combine two streams — the latest value of each.
Stream<R> _combine<A, B, R>(Stream<A> a, Stream<B> b, R Function(A, B) f) {
  late StreamController<R> c;
  A? na;
  B? nb;
  var hasA = false;
  var hasB = false;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  void push() {
    if (hasA && hasB) c.add(f(na as A, nb as B));
  }

  c = StreamController<R>(
    onListen: () {
      sa = a.listen((v) {
        na = v;
        hasA = true;
        push();
      }, onError: c.addError);
      sb = b.listen((v) {
        nb = v;
        hasB = true;
        push();
      }, onError: c.addError);
    },
    onPause: () {
      sa?.pause();
      sb?.pause();
    },
    onResume: () {
      sa?.resume();
      sb?.resume();
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return c.stream;
}
