import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:monotonic_clock/monotonic_clock.dart';

import '../db/app_database.dart';
import '../device/notifications.dart';
import '../network/api_client.dart';
import '../network/api_error.dart';
import '../config/env.dart';
import '../session/session.dart';
import '../util/app_log.dart';
import '../util/clock_drift.dart';
import '../util/app_version.dart';
import '../util/format.dart';

/// Summary of one sync round — for the banner on Home and the background log.
class SyncResult {
  SyncResult();

  int sent = 0;
  int deferred = 0;
  int rejected = 0;
  int failed = 0;
  int photosSent = 0;
  int photosRejected = 0;
  bool pulled = false;

  /// The sync lock is held by another isolate (screen vs background) — not an error.
  bool busy = false;
  bool sessionExpired = false;
  bool offline = false;
  String? error;

  /// The server refused this app version; nothing was sent or pulled.
  AppOutdated? outdated;

  bool get success => error == null && !sessionExpired && !offline && !busy;

  @override
  String toString() => 'sent $sent, deferred $deferred, rejected $rejected, failed $failed, '
      'photos $photosSent/$photosRejected, pulled $pulled${error == null ? '' : ', error: $error'}';
}

/// Sync engine: PUSH documents → PUSH photos → PULL master data.
///
/// THE ORDER IS DELIBERATE
///
/// 1. Documents first. An attendance record is a few hundred bytes; a photo is tens of kB. On a
///    one-bar signal, the light attendance record must already be in before the photo starts
///    eating up the time. The server flags `FOTO_BELUM_MASUK` while the photo is
///    still on its way, and the flag clears by itself when the photo arrives.
/// 2. Photos, one per request — one failure does not repeat the others.
/// 3. Pull last, so the pulled status already includes what was just
///    pushed (e.g. a point that was just marked as drilled).
///
/// ONLY ONE AT A TIME
///
/// The screen ("Kirim sekarang" button) and the background worker can run
/// at the same time in different isolates. Without a lock, both take the SAME queue
/// and push it twice. The server is safe against that anyway
/// (the same version is answered with `duplikat`), but the foreman's data quota is not.
/// Meta key holding [AppOutdated] while the server refuses this version.
const appOutdatedKey = 'app_outdated';

class SyncEngine {
  SyncEngine({required this.db, required this.api, required this.session});

  final AppDatabase db;
  final ApiClient api;
  final SessionStore session;

  static const _lockTtl = Duration(minutes: 3);
  static const _maxPushRounds = 20;
  static const _maxPullPages = 20;

  Dio get _dio => api.dio;

  Future<SyncResult> run({bool push = true, bool pull = true}) async {
    final result = SyncResult();
    final user = await session.user();
    if (user == null || await session.accessToken() == null) {
      result.sessionExpired = true;
      return result;
    }
    if (await session.sessionExpired()) {
      result.sessionExpired = true;
      return result;
    }

    final owner = newUuid();
    if (!await db.acquireLock('sync', owner, _lockTtl)) {
      result.busy = true;
      return result;
    }
    try {
      if (push) {
        await _pushDocuments(user.id, owner, result);
        await _pushPhotos(user.id, owner, result);
      }
      if (pull) await _pull(user.id, owner, result);
      await db.writeMeta('last_sync', isoWithOffset(DateTime.now()));
    } on ApiError catch (e) {
      if (e.appOutdated) {
        result.outdated = AppOutdated.fromContext(e.context);
        result.error = e.message;
        // Kept on the phone: the app shows the update screen until a new
        // enough version is installed (see appOutdatedProvider).
        await db.writeMeta(appOutdatedKey, result.outdated!.encode());
      } else if (e.sessionExpired) {
        result.sessionExpired = true;
      } else if (e.offline) {
        result.offline = true;
      } else {
        result.error = e.message;
        AppLog.error('sync', '${e.code}: ${e.message}');
      }
    } catch (e, st) {
      result.error = e.toString();
      AppLog.error('sync', e, st);
    } finally {
      await db.releaseLock('sync', owner);
    }
    if (result.error != null) await db.writeMeta('last_sync_error', result.error);
    // Served again (e.g. the minimum was lowered): lift the update screen.
    if (result.success) await db.writeMeta(appOutdatedKey, null);
    return result;
  }

  /// Extend the lock between long rounds (photo uploads on a weak signal
  /// can outlast the lock's TTL).
  Future<void> _extendLock(String owner) => db.acquireLock('sync', owner, _lockTtl);

  // -------------------------------------------------------------------------
  // Push documents
  // -------------------------------------------------------------------------

  Future<void> _pushDocuments(int userId, String owner, SyncResult result) async {
    for (var round = 0; round < _maxPushRounds; round++) {
      final queue = await db.sendQueue(userId, limits: Env.itemsPerPush);
      if (queue.isEmpty) return;
      await _extendLock(owner);

      final clock = await MonotonicClock.read();
      final payload = <String, Object?>{
        'sentAtDevice': isoWithOffset(DateTime.now()),
        'sentElapsedMs': clock?.elapsedMs,
        'bootCount': clock?.bootCount,
        'items': [
          for (final d in queue)
            {
              'entity': d.entity,
              'uuid': d.uuid,
              'version': d.version,
              'data': jsonDecode(d.body),
            },
        ],
      };

      final Map<String, dynamic> reply;
      try {
        final r = await _dio.post<Map<String, dynamic>>('/field/sync/push', data: payload);
        reply = r.data ?? const {};
      } catch (e) {
        throw ApiError.from(e);
      }

      final byUuid = <String, Map<String, Object?>>{};
      for (final h in (reply['results'] as List?) ?? const []) {
        final m = (h as Map).cast<String, Object?>();
        byUuid['${m['uuid']}'] = m;
      }

      var madeProgress = false;
      for (final d in queue) {
        final h = byUuid[d.uuid];
        // No reply for this item = treat as failed, retry later.
        final status = (h?['status'] ?? 'gagal').toString();
        await db.recordResponse(
          uuid: d.uuid,
          sentVersion: d.version,
          status: status,
          reason: h?['reason']?.toString(),
          detail: h?['detail']?.toString(),
          flags: h?['flags'] == null ? null : jsonEncode(h!['flags']),
          serverId: toIntOrNull(h?['id']),
        );
        switch (status) {
          case 'ok' || 'duplikat':
            result.sent++;
            madeProgress = true;
          case 'tertunda':
            result.deferred++;
          case 'ditolak':
            result.rejected++;
            madeProgress = true; // leaves the queue, not stuck
          default:
            result.failed++;
        }
      }
      // All failed/deferred: a delay was already applied, the next round will only
      // pick up the remainder that has not been tried yet — or nothing.
      if (!madeProgress && queue.length < Env.itemsPerPush) return;
    }
  }

  // -------------------------------------------------------------------------
  // Push photos
  // -------------------------------------------------------------------------

  Future<void> _pushPhotos(int userId, String owner, SyncResult result) async {
    for (var round = 0; round < 10; round++) {
      final queue = await db.photoQueue(userId);
      if (queue.isEmpty) return;
      for (final f in queue) {
        await _extendLock(owner);
        await _uploadOne(f, result);
      }
      if (queue.length < 20) return;
    }
  }

  Future<void> _uploadOne(PhotoRow f, SyncResult result) async {
    final file = File(f.path);
    if (!await file.exists()) {
      // File is gone (cleaned up by the system / app was reinstalled).
      // Nothing can be sent anymore; mark it rejected so the queue
      // does not get stuck, and the server keeps flagging FOTO_BELUM_MASUK.
      await db.recordPhotoResult(f.uuid, status: 'rejected', reason: 'BERKAS_HILANG');
      result.photosRejected++;
      return;
    }
    final bytes = await file.readAsBytes();
    try {
      await _dio.put<dynamic>(
        '/field/photos/${f.uuid}',
        data: Stream<List<int>>.value(bytes),
        options: Options(
          contentType: 'image/jpeg',
          sendTimeout: const Duration(minutes: 2),
          headers: {
            Headers.contentLengthHeader: bytes.length,
            'X-Photo-Kind': f.kind,
            'X-Photo-Sha256': f.sha256,
            'X-Photo-Taken-At': isoWithOffset(f.takenAt),
            if (f.faceCount != null) 'X-Photo-Face-Count': '${f.faceCount}',
            if (f.lat != null) 'X-Photo-Lat': f.lat!.toStringAsFixed(7),
            if (f.lng != null) 'X-Photo-Lng': f.lng!.toStringAsFixed(7),
          },
        ),
      );
      await db.recordPhotoResult(f.uuid, status: 'sent');
      result.photosSent++;
    } catch (e) {
      final g = ApiError.from(e);
      if (g.offline || g.sessionExpired) throw g;
      final s = g.status ?? 0;
      if (s >= 400 && s < 500 && s != 408 && s != 429) {
        // Rejected because of its content (not a JPEG, too large, uuid conflict,
        // not authorized): retrying will not change the answer.
        await db.recordPhotoResult(f.uuid, status: 'rejected', reason: g.code ?? g.message);
        result.photosRejected++;
      } else {
        await db.recordPhotoResult(f.uuid, status: 'failed', reason: g.message);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  Future<void> _pull(int userId, String owner, SyncResult result) async {
    final cursorKey = 'cursor:$userId';
    var cursor = await db.readMeta(cursorKey);
    for (var page = 0; page < _maxPullPages; page++) {
      await _extendLock(owner);
      final Map<String, dynamic> d;
      final currentCursor = cursor;
      try {
        final r = await _dio.get<Map<String, dynamic>>(
          '/field/sync/pull',
          queryParameters: {if (currentCursor != null && currentCursor.isNotEmpty) 'cursor': currentCursor},
        );
        d = r.data ?? const {};
      } catch (e) {
        throw ApiError.from(e);
      }

      // Drill logs the office deleted: their "no reading for an hour" buzz
      // must stop too. Cancelled after the transaction, not inside it.
      final deletedDrillLogs = <String>[];
      await db.transaction(() async {
        final projects = d['projects'];
        if (projects is List) {
          await db.replaceAllProjects([for (final p in projects) (p as Map).cast<String, Object?>()]);
        }
        for (final w in (d['workers'] as List?) ?? const []) {
          final m = (w as Map).cast<String, Object?>();
          await db.upsertMaster('worker', '${m['uuid']}', m, deleted: m['isDelete'] == true);
        }
        for (final t in (d['pilePoints'] as List?) ?? const []) {
          final m = (t as Map).cast<String, Object?>();
          await db.upsertMaster('pile_point', '${m['uuid']}', m, deleted: m['isDelete'] == true);
        }
        for (final a in (d['attendanceStatus'] as List?) ?? const []) {
          final m = (a as Map).cast<String, Object?>();
          await db.recordServerStatus('${m['uuid']}', '${m['status']}', m['reviewNote']?.toString());
        }
        for (final c in (d['castingStatus'] as List?) ?? const []) {
          final m = (c as Map).cast<String, Object?>();
          if (m['isDelete'] == true) {
            // Deleted by the office: drop the phone's copy so the point opens again.
            await db.deleteDocument('${m['uuid']}');
          } else {
            await db.recordServerStatus('${m['uuid']}', '${m['status']}', m['note']?.toString());
          }
        }
        for (final c in (d['drillLogStatus'] as List?) ?? const []) {
          final m = (c as Map).cast<String, Object?>();
          if (m['isDelete'] == true) {
            await db.deleteDocument('${m['uuid']}');
            deletedDrillLogs.add('${m['uuid']}');
          }
        }
        final suppliers = d['concreteSuppliers'];
        if (suppliers is List) {
          await db.replaceAllMasters('supplier', [for (final s in suppliers) (s as Map).cast<String, Object?>()]);
        }
        cursor = d['cursor']?.toString();
        await db.writeMeta(cursorKey, cursor);
        final serverTime = d['serverTime']?.toString();
        if (serverTime != null) await db.writeMeta('server_time', '$serverTime|${DateTime.now().toIso8601String()}');
        // Every reading and TM time comes from the phone clock: a clock that
        // is off by much makes the log wrong in a way nobody can see later.
        final drift = clockDriftOf('$serverTime|${DateTime.now().toIso8601String()}');
        if (drift != null && drift.abs() > clockDriftWarn) {
          AppLog.info('clock', 'phone clock off by ${drift.inMinutes} min from server');
        }
      });
      for (final uuid in deletedDrillLogs) {
        try {
          await Notifications.cancelDrillIdleReminders(uuid);
        } catch (_) {
          // No notification plugin here (e.g. a test): nothing to cancel.
        }
      }
      result.pulled = true;
      if (d['hasMore'] != true) return;
    }
  }
}
