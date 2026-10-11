import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ===========================================================================
// LOCAL STORAGE SHAPE — and why not one table per entity
//
// The server accepts whole VERSIONED DOCUMENTS: an attendance with all its
// worker lines, a casting log with all its TMs and tremie segments. So the
// phone also stores whole documents: one row in `Documents`, its body JSON
// exactly as it will be sent.
//
// What this shape buys us:
//
//   * THE SEND QUEUE CANNOT BE FORGOTTEN. Saving = bumping `version`.
//     Not yet sent = `version > syncedVersion`. There is no separate queue
//     table that must be filled in at the same time (and one day be forgotten).
//
//   * Re-sending is safe: the server rejects versions that are not newer.
//
// Master data from the server (projects, workers, points) is stored in
// `MasterRecords`, also as JSON — the phone never writes it, only replaces it from a pull.
// ===========================================================================

@DataClassName('MasterRecord')
class MasterRecords extends Table {
  /// project | worker | pile_point
  TextColumn get entity => text()();

  /// server id (project) or uuid (worker, pile point).
  TextColumn get key => text()();
  TextColumn get body => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {entity, key};
}

@DataClassName('DocumentRow')
class Documents extends Table {
  TextColumn get uuid => text()();

  /// worker | attendance | drill_mark | casting — same as the server.
  TextColumn get entity => text()();

  /// The queue is bound to the USER. If someone else logs in on the same phone,
  /// the previous user's documents are not sent on their behalf.
  IntColumn get userId => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get syncedVersion => integer().withDefault(const Constant(0))();
  TextColumn get body => text()();

  /// pending | sent | deferred | rejected | failed
  TextColumn get sendStatus => text().withDefault(const Constant('pending'))();
  TextColumn get reason => text().nullable()();
  TextColumn get detail => text().nullable()();

  /// Fraud flags from the server (JSON), for the banner on the phone.
  TextColumn get flags => text().nullable()();
  IntColumn get serverId => integer().nullable()();

  /// Status on the server: dikirim/ditinjau/ditolak (attendance),
  /// berjalan/selesai/diperiksa (casting). Filled in from the pull.
  TextColumn get serverStatus => text().nullable()();
  TextColumn get serverNote => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get retryAfter => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {uuid};
}

@DataClassName('PhotoRow')
class Photos extends Table {
  TextColumn get uuid => text()();

  /// wajah | absen_masuk | absen_pulang | tiket_tm
  TextColumn get kind => text()();
  TextColumn get path => text()();
  TextColumn get sha256 => text()();
  IntColumn get sizeBytes => integer()();
  IntColumn get faceCount => integer().nullable()();
  DateTimeColumn get takenAt => dateTime()();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  IntColumn get userId => integer()();

  /// pending | sent | rejected | failed (failed is passed in by the sync engine and
  /// stored back as pending with a retry delay)
  TextColumn get sendStatus => text().withDefault(const Constant('pending'))();
  TextColumn get reason => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get retryAfter => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {uuid};
}

@DataClassName('MetaRow')
class LocalMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Send order: workers first (referenced by attendance), drill marks before casting.
/// A drill log goes before the drill marks: a mark sent later corrects it.
const entityOrder = {'worker': 0, 'drill_log': 1, 'drill_mark': 2, 'attendance': 3, 'casting': 4};

@DriftDatabase(tables: [MasterRecords, Documents, Photos, LocalMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  /// 2: tables renamed to English. Version 1 shipped in two shapes (the
  /// first build used Indonesian table names), so the upgrade drops the old
  /// names and [_createMissingTables] builds whatever is not there.
  @override
  int get schemaVersion => 2;

  /// Tables of the first build, before the rename.
  static const _retiredTables = ['induk', 'dokumen', 'foto', 'meta_lokal'];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            for (final old in _retiredTables) {
              await customStatement('DROP TABLE IF EXISTS "$old"');
            }
          }
        },
        // Runs on every open, so a phone whose file is missing a table for
        // any reason heals itself instead of failing with "no such table".
        beforeOpen: (_) => _createMissingTables(),
      );

  Future<void> _createMissingTables() async {
    final rows = await customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
    final present = {for (final r in rows) r.read<String>('name')};
    final m = createMigrator();
    for (final t in allTables) {
      if (!present.contains(t.actualTableName)) await m.createTable(t);
    }
  }

  /// Shared across isolates: the screen and the background worker (workmanager) open
  /// the SAME file, through a single drift isolate.
  static QueryExecutor _open() => driftDatabase(
        name: 'terrabot_field',
        native: const DriftNativeOptions(shareAcrossIsolates: true),
      );

  // -------------------------------------------------------------------------
  // Meta
  // -------------------------------------------------------------------------

  Future<String?> readMeta(String key) async {
    final rows = await (select(localMeta)..where((t) => t.key.equals(key))).getSingleOrNull();
    return rows?.value;
  }

  /// Follows one meta value; emits null while it is unset.
  Stream<String?> watchMeta(String key) =>
      (select(localMeta)..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> writeMeta(String key, String? value) =>
      into(localMeta).insertOnConflictUpdate(LocalMetaCompanion.insert(key: key, value: Value(value)));

  /// Time-limited cross-isolate lock. `true` if it was acquired.
  ///
  /// Used for two things that MUST NOT run twice at once: sync
  /// (screen and background pushing the same document simultaneously) and token
  /// refresh (two simultaneous refreshes = old token used twice = the whole
  /// session revoked by the server).
  Future<bool> acquireLock(String name, String owner, Duration ttl) {
    return transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await readMeta('lock:$name');
      if (existing != null) {
        final parts = existing.split('|');
        final expiresAt = parts.length == 2 ? int.tryParse(parts[1]) ?? 0 : 0;
        if (parts[0] != owner && expiresAt > now) return false;
      }
      await writeMeta('lock:$name', '$owner|${now + ttl.inMilliseconds}');
      return true;
    });
  }

  Future<void> releaseLock(String name, String owner) async {
    await transaction(() async {
      final existing = await readMeta('lock:$name');
      if (existing != null && existing.split('|').first == owner) {
        await writeMeta('lock:$name', null);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Induk
  // -------------------------------------------------------------------------

  Future<void> upsertMaster(String entity, String key, Map<String, Object?> body, {bool deleted = false}) {
    return into(masterRecords).insertOnConflictUpdate(
      MasterRecordsCompanion.insert(
        entity: entity,
        key: key,
        body: jsonEncode(body),
        deleted: Value(deleted),
      ),
    );
  }

  /// Projects are always pushed WHOLE — those missing from the new list are deleted.
  Future<void> replaceAllProjects(List<Map<String, Object?>> projects) {
    return transaction(() async {
      await (delete(masterRecords)..where((t) => t.entity.equals('project'))).go();
      for (final p in projects) {
        await upsertMaster('project', '${p['id']}', p);
      }
    });
  }

  /// A small list the server always sends WHOLE (e.g. concrete suppliers):
  /// whatever is missing from it is gone.
  Future<void> replaceAllMasters(String entity, List<Map<String, Object?>> rows, {String keyField = 'id'}) {
    return transaction(() async {
      await (delete(masterRecords)..where((t) => t.entity.equals(entity))).go();
      for (final r in rows) {
        await upsertMaster(entity, '${r[keyField]}', r);
      }
    });
  }

  /// Another user logs in on this phone: master data and the pull cursor are dropped
  /// so they are pulled again according to the NEW user's rights (foreman A's crew must not
  /// show up on foreman B's phone). Documents and photos are NOT touched —
  /// the previous user's queue stays intact and is sent when they log in again.
  Future<void> switchUser() {
    return transaction(() async {
      await delete(masterRecords).go();
      await (delete(localMeta)..where((t) => t.key.like('cursor%'))).go();
    });
  }

  Stream<List<Map<String, Object?>>> watchMaster(String entity) {
    final q = select(masterRecords)
      ..where((t) => t.entity.equals(entity) & t.deleted.equals(false));
    return q.watch().map((rows) => [for (final b in rows) _decodeMap(b.body)]);
  }

  Future<List<Map<String, Object?>>> listMaster(String entity) async {
    final q = select(masterRecords)
      ..where((t) => t.entity.equals(entity) & t.deleted.equals(false));
    return [for (final b in await q.get()) _decodeMap(b.body)];
  }

  Future<Map<String, Object?>?> getMaster(String entity, String key) async {
    final b = await (select(masterRecords)..where((t) => t.entity.equals(entity) & t.key.equals(key)))
        .getSingleOrNull();
    if (b == null || b.deleted) return null;
    return _decodeMap(b.body);
  }

  // -------------------------------------------------------------------------
  // Dokumen
  // -------------------------------------------------------------------------

  /// Saving a document = ONE write that also puts it in the queue.
  ///
  /// [serverVersion] — for documents that ORIGINATE from the server (e.g. a worker
  /// edited from the phone): its first local version must exceed the server's
  /// version, otherwise the server answers `duplikat` and the change is
  /// silently not applied.
  Future<void> saveDocument({
    required String uuid,
    required String entity,
    required int userId,
    required Map<String, Object?> body,
    int? serverVersion,
  }) {
    return transaction(() async {
      final now = DateTime.now();
      final existing = await getDocument(uuid);
      if (existing == null) {
        final base = serverVersion ?? 0;
        await into(documents).insert(
          DocumentsCompanion.insert(
            uuid: uuid,
            entity: entity,
            userId: userId,
            body: jsonEncode(body),
            version: Value(base + 1),
            syncedVersion: Value(base),
            createdAt: now,
            updatedAt: now,
          ),
        );
      } else {
        await (update(documents)..where((t) => t.uuid.equals(uuid))).write(
          DocumentsCompanion(
            body: Value(jsonEncode(body)),
            version: Value(existing.version + 1),
            sendStatus: const Value('pending'),
            reason: const Value(null),
            detail: const Value(null),
            attempts: const Value(0),
            retryAfter: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Read, change and store ONE document inside a single transaction.
  ///
  /// The screen is no longer the only writer: the "Selesai TM" button on the
  /// stopwatch notification closes a truck while the casting screen may be
  /// open, and a smartwatch button does the same later. [saveDocument] takes a
  /// body the caller built earlier, so two writers would each write away the
  /// other's fields — silently, because the version still goes up. Here the
  /// STORED body is read inside the transaction and handed to [mutate].
  ///
  /// [createWith] is the starting body when the document is not on the phone
  /// yet (a new casting log is only stored on its first change).
  ///
  /// Returns the stored body after the change, or null when there is nothing
  /// to change and no [createWith].
  Future<Map<String, Object?>?> mutateDocument({
    required String uuid,
    required String entity,
    required int userId,
    required void Function(Map<String, Object?> body) mutate,
    Map<String, Object?>? createWith,
  }) {
    return transaction(() async {
      final existing = await getDocument(uuid);
      // A deep copy, so a caller's [createWith] is never aliased into state
      // the caller keeps editing.
      final Map<String, Object?>? body = existing != null
          ? _decodeMap(existing.body)
          : createWith == null
              ? null
              : (_decodeMap(jsonEncode(createWith)));
      if (body == null) return null;
      mutate(body);
      await saveDocument(uuid: uuid, entity: entity, userId: userId, body: body);
      return body;
    });
  }

  Future<DocumentRow?> getDocument(String uuid) =>
      (select(documents)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Stream<DocumentRow?> watchDocument(String uuid) =>
      (select(documents)..where((t) => t.uuid.equals(uuid))).watchSingleOrNull();

  /// Remove a REJECTED document from the phone (the foreman chose not to fix it).
  /// Only those that are rejected or have never been sent at all.
  Future<void> discardDocument(String uuid) => (delete(documents)
        ..where((t) => t.uuid.equals(uuid) & (t.sendStatus.equals('rejected') | t.syncedVersion.equals(0))))
      .go();

  /// Re-send rejected ones AFTER they were fixed elsewhere (e.g. an admin
  /// filled in the project's concrete grade). The version is bumped so the server processes it.
  Future<void> retryDocument(String uuid) {
    return transaction(() async {
      final existing = await getDocument(uuid);
      if (existing == null) return;
      await (update(documents)..where((t) => t.uuid.equals(uuid))).write(
        DocumentsCompanion(
          version: Value(existing.version + 1),
          sendStatus: const Value('pending'),
          reason: const Value(null),
          detail: const Value(null),
          attempts: const Value(0),
          retryAfter: const Value(null),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// All documents whose business is not yet finished, for the Queue screen.
  Stream<List<DocumentRow>> watchQueue(int userId) {
    final q = select(documents)
      ..where((t) =>
          t.userId.equals(userId) &
          (t.version.isBiggerThan(t.syncedVersion) | t.sendStatus.isIn(const ['rejected', 'deferred', 'failed'])))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch();
  }

  Stream<List<PhotoRow>> watchPendingPhotos(int userId) {
    final q = select(photos)
      ..where((t) => t.userId.equals(userId) & t.sendStatus.isNotIn(const ['sent']))
      ..orderBy([(t) => OrderingTerm.desc(t.takenAt)]);
    return q.watch();
  }

  Stream<List<DocumentRow>> watchDocuments(String entity, int userId) {
    final q = select(documents)
      ..where((t) => t.entity.equals(entity) & t.userId.equals(userId))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch();
  }

  /// What is waiting to be sent for this user, in a safe order.
  Future<List<DocumentRow>> sendQueue(int userId, {int limits = 50}) async {
    final now = DateTime.now();
    final q = select(documents)
      ..where((t) =>
          t.userId.equals(userId) &
          t.version.isBiggerThan(t.syncedVersion) &
          t.sendStatus.isNotIn(const ['rejected']) &
          (t.retryAfter.isNull() | t.retryAfter.isSmallerOrEqualValue(now)))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final all = await q.get();
    all.sort((a, b) {
      final ua = entityOrder[a.entity] ?? 9;
      final ub = entityOrder[b.entity] ?? 9;
      return ua != ub ? ua.compareTo(ub) : a.createdAt.compareTo(b.createdAt);
    });
    return all.take(limits).toList();
  }

  Stream<int> watchPendingCount(int userId) {
    final count = documents.uuid.count();
    final q = selectOnly(documents)
      ..addColumns([count])
      ..where(documents.userId.equals(userId) &
          documents.version.isBiggerThan(documents.syncedVersion) &
          documents.sendStatus.isNotIn(const ['rejected']));
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  Stream<int> watchRejectedCount(int userId) {
    final count = documents.uuid.count();
    final q = selectOnly(documents)
      ..addColumns([count])
      ..where(documents.userId.equals(userId) & documents.sendStatus.equals('rejected'));
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  /// Record the server's response to ONE document.
  ///
  /// `sentVersion` — the version that was sent. If the document is changed again while
  /// the push is in flight (its version is now higher), only that version is marked
  /// as sent; later changes stay in the queue.
  Future<void> recordResponse({
    required String uuid,
    required int sentVersion,
    required String status,
    String? reason,
    String? detail,
    String? flags,
    int? serverId,
  }) {
    return transaction(() async {
      final existing = await getDocument(uuid);
      if (existing == null) return;
      final success = status == 'ok' || status == 'duplikat';
      final attempts = success ? 0 : existing.attempts + 1;
      await (update(documents)..where((t) => t.uuid.equals(uuid))).write(
        DocumentsCompanion(
          syncedVersion: success ? Value(sentVersion) : const Value.absent(),
          sendStatus: Value(switch (status) {
            'ok' || 'duplikat' => existing.version > sentVersion ? 'pending' : 'sent',
            'tertunda' => 'deferred',
            'ditolak' => 'rejected',
            _ => 'failed',
          }),
          reason: Value(reason),
          detail: Value(detail),
          flags: flags == null ? const Value.absent() : Value(flags),
          serverId: serverId == null ? const Value.absent() : Value(serverId),
          attempts: Value(attempts),
          retryAfter: Value(success || status == 'ditolak' ? null : DateTime.now().add(retryDelay(attempts))),
        ),
      );
    });
  }

  /// The office deleted this document (a casting / drill log logged on the
  /// wrong point): the phone's copy goes too, so the point opens again.
  Future<void> deleteDocument(String uuid) =>
      (delete(documents)..where((t) => t.uuid.equals(uuid))).go();

  /// When the oldest change still waiting to be sent was made — documents
  /// and photos. Null when nothing is waiting.
  Stream<DateTime?> watchOldestPending(int userId) {
    final oldestDoc = documents.updatedAt.min();
    final docs = (selectOnly(documents)
          ..addColumns([oldestDoc])
          ..where(documents.userId.equals(userId) &
              documents.version.isBiggerThan(documents.syncedVersion) &
              documents.sendStatus.isNotIn(const ['rejected'])))
        .watchSingle()
        .map((r) => r.read(oldestDoc));
    final oldestPhoto = photos.takenAt.min();
    final pics = (selectOnly(photos)
          ..addColumns([oldestPhoto])
          ..where(photos.userId.equals(userId) & photos.sendStatus.equals('pending')))
        .watchSingle()
        .map((r) => r.read(oldestPhoto));
    // Combined by hand (no rxdart): re-emit whenever either side changes.
    DateTime? d;
    DateTime? p;
    DateTime? older() => d == null ? p : (p == null || d!.isBefore(p!) ? d : p);
    late final StreamController<DateTime?> out;
    StreamSubscription<DateTime?>? a;
    StreamSubscription<DateTime?>? b;
    out = StreamController<DateTime?>(
      onListen: () {
        a = docs.listen((v) {
          d = v;
          out.add(older());
        }, onError: out.addError);
        b = pics.listen((v) {
          p = v;
          out.add(older());
        }, onError: out.addError);
      },
      onCancel: () async {
        await a?.cancel();
        await b?.cancel();
      },
    );
    return out.stream;
  }

  Future<void> recordServerStatus(String uuid, String status, String? note) {
    return (update(documents)..where((t) => t.uuid.equals(uuid))).write(
      DocumentsCompanion(serverStatus: Value(status), serverNote: Value(note)),
    );
  }

  // -------------------------------------------------------------------------
  // Foto
  // -------------------------------------------------------------------------

  Future<void> insertPhoto(PhotosCompanion rows) => into(photos).insert(rows);

  Future<PhotoRow?> getPhoto(String uuid) =>
      (select(photos)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();

  Future<List<PhotoRow>> photoQueue(int userId, {int limits = 20}) {
    final now = DateTime.now();
    final q = select(photos)
      ..where((t) =>
          t.userId.equals(userId) &
          t.sendStatus.equals('pending') &
          (t.retryAfter.isNull() | t.retryAfter.isSmallerOrEqualValue(now)))
      ..orderBy([(t) => OrderingTerm.asc(t.takenAt)])
      ..limit(limits);
    return q.get();
  }

  Stream<int> watchPendingPhotoCount(int userId) {
    final count = photos.uuid.count();
    final q = selectOnly(photos)
      ..addColumns([count])
      ..where(photos.userId.equals(userId) & photos.sendStatus.equals('pending'));
    return q.watchSingle().map((r) => r.read(count) ?? 0);
  }

  Future<void> recordPhotoResult(String uuid, {required String status, String? reason}) {
    return transaction(() async {
      final existing = await getPhoto(uuid);
      if (existing == null) return;
      final success = status == 'sent';
      final attempts = success ? 0 : existing.attempts + 1;
      await (update(photos)..where((t) => t.uuid.equals(uuid))).write(
        PhotosCompanion(
          sendStatus: Value(status == 'failed' ? 'pending' : status),
          reason: Value(reason),
          attempts: Value(attempts),
          retryAfter: Value(status == 'failed' ? DateTime.now().add(retryDelay(attempts)) : null),
        ),
      );
    });
  }
}

/// Delay before retrying: 30 s, 1, 2, 4, ... max 30 minutes.
Duration retryDelay(int attempts) {
  final secs = 30 * (1 << (attempts.clamp(1, 7) - 1));
  return Duration(seconds: secs > 1800 ? 1800 : secs);
}

Map<String, Object?> _decodeMap(String json) => (jsonDecode(json) as Map).cast<String, Object?>();
