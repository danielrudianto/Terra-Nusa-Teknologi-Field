import 'dart:async';

import 'package:dio/dio.dart';

import '../db/app_database.dart';
import '../config/env.dart';
import '../session/session.dart';
import '../util/format.dart';
import 'api_error.dart';

/// HTTP client to the TerraBot backend.
///
/// TOKEN REFRESH — ONLY ONE, ACROSS THE WHOLE APP
///
/// A TerraBot refresh token is valid only ONCE. Two simultaneous refreshes
/// with the same token are read by the server as a stolen token, and the
/// ENTIRE session is revoked. On a phone, two simultaneous refreshes happen
/// easily: the screen and the background worker (workmanager) run in
/// different isolates, and both can receive a 401 at the same time.
///
/// For that reason the refresh uses a cross-isolate lock in the local database,
/// and before refreshing, the stored token is re-checked: if it already differs
/// from the rejected one, another isolate has just refreshed it and this one
/// simply uses the result.
class ApiClient {
  ApiClient({required this.db, required this.session, required this.deviceId, this.deviceName}) {
    dio = Dio(
      BaseOptions(
        baseUrl: Env.apiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {
          'X-Device-Id': deviceId,
          'X-App-Version': Env.appVersion,
          'X-Os-Version': 'android',
          // Merek dan tipe HP. Server memakainya untuk menamai perangkat pada
          // peringatan "akun ini dipakai di HP lain"; tanpa ini yang tampil
          // adalah user-agent Dart, yang sama di semua HP.
          'X-Device-Name': ?deviceName,
        },
      ),
    );
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (opts, handler) async {
          final access = await session.accessToken();
          if (access != null && !opts.path.startsWith('/auth/')) {
            opts.headers['Authorization'] = 'Bearer $access';
          }
          handler.next(opts);
        },
        onError: (error, handler) async {
          final opts = error.requestOptions;
          final alreadyRetried = opts.extra['retried'] == true;
          if (error.response?.statusCode != 401 || alreadyRetried || opts.path.startsWith('/auth/')) {
            return handler.next(error);
          }
          final rejected = (opts.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
          final success = await _refresh(rejected);
          if (!success) return handler.next(error);
          try {
            final fresh = await session.accessToken();
            opts.headers['Authorization'] = 'Bearer $fresh';
            opts.extra['retried'] = true;
            handler.resolve(await dio.fetch<dynamic>(opts));
          } on DioException catch (e) {
            handler.next(e);
          }
        },
      ),
    );
  }

  final AppDatabase db;
  final SessionStore session;
  final String deviceId;

  /// Merek dan tipe HP, bila terbaca. Null = server memakai user-agent.
  final String? deviceName;
  late final Dio dio;

  /// Called when the refresh token is rejected (the session has truly expired).
  void Function()? onSessionExpired;

  Future<bool> _refresh(String? rejectedAccess) async {
    final owner = newUuid();
    var acquired = false;
    for (var i = 0; i < 40 && !acquired; i++) {
      acquired = await db.acquireLock('token', owner, const Duration(seconds: 30));
      if (!acquired) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    try {
      // Did another isolate already refresh while we were waiting?
      final now = await session.accessToken();
      if (now != null && now != rejectedAccess) return true;
      if (!acquired) return false;

      final refresh = await session.refreshToken();
      if (refresh == null) {
        await _expire();
        return false;
      }
      final plain = Dio(BaseOptions(baseUrl: Env.apiUrl, connectTimeout: const Duration(seconds: 15)));
      final r = await plain.post<Map<String, dynamic>>(
        '/auth/refresh',
        options: Options(headers: {
          // Header, not cookie: a native app has no browser cookie jar.
          // This path is PERMANENT on the server (see auth_routes.py).
          'x-refresh-token': 'Bearer $refresh',
          'X-Device-Id': deviceId,
          'X-App-Version': Env.appVersion,
          // Penyegaran juga menulis baris perangkat di server, jadi namanya
          // ikut di sini — kalau tidak, labelnya berubah-ubah sendiri.
          'X-Device-Name': ?deviceName,
        }),
      );
      final data = r.data ?? const {};
      final access = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (access == null || newRefresh == null) return false;
      await session.writeTokens(access, newRefresh);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await _expire();
      // No signal: not an expired session. Retried on the next push.
      return false;
    } finally {
      if (acquired) await db.releaseLock('token', owner);
    }
  }

  Future<void> _expire() async {
    await session.markSessionExpired();
    onSessionExpired?.call();
  }

  // -------------------------------------------------------------------------

  /// [moveDevice] answers the server's "this account is still signed in on
  /// another phone": true means "yes, move it here". Sent only after the
  /// person has said so — never on the first attempt.
  Future<(AppUser, String, String)> login(String email, String password, {bool moveDevice = false}) async {
    try {
      final r = await dio.post<Map<String, dynamic>>('/auth/', data: {
        'email': email.trim(),
        'password': password,
        if (moveDevice) 'pindahkanPerangkat': true,
      });
      final data = r.data ?? const {};
      final user = AppUser.fromJson((data['user'] as Map).cast<String, Object?>());
      return (user, data['access_token'] as String, data['refresh_token'] as String);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<PermissionMap> permissions() async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/permissions/me');
      return PermissionMap.fromJson((r.data ?? const {}).cast<String, Object?>());
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Points drilled and cast from [from] to [to] (directors only, level 5+).
  Future<Map<String, Object?>> report(DateTime from, DateTime to, {int? projectId}) async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/field/reports', queryParameters: {
        'dateFrom': isoDate(from),
        'dateTo': isoDate(to),
        'projectID': ?projectId,
      });
      return (r.data ?? const {}).cast<String, Object?>();
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// "Rekapitulasi Data Tiang" as .xlsx bytes. No [from] = since the start.
  ///
  /// [sheets] names which sheets the server builds (tiang / beton /
  /// operator / pemasok). Empty means ALL of them — which is also what an
  /// older server does with the parameter it does not know, so neither side
  /// breaks, and a sheet added later reaches old phones that send nothing.
  Future<List<int>> reportExcel({
    DateTime? from,
    required DateTime to,
    int? projectId,
    List<String> sheets = const [],
  }) async {
    try {
      final r = await dio.get<List<int>>(
        '/field/reports/excel',
        queryParameters: {
          'dateFrom': ?(from == null ? null : isoDate(from)),
          'dateTo': isoDate(to),
          'projectID': ?projectId,
          if (sheets.isNotEmpty) 'sheets': sheets.join(','),
        },
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)),
      );
      return r.data ?? const [];
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// One field photo's bytes, from the server.
  ///
  /// The phone that TOOK the photo keeps its own copy on disk and never
  /// needs this. Every OTHER phone does: a delivery ticket photographed at
  /// the mixer truck is the one page a watcher actually wants to read, and
  /// until now it only existed on the recorder's phone.
  ///
  /// 410 from the server = the photo existed but is past its retention; the
  /// caller shows that as a sentence, not as a failure to load.
  Future<List<int>> fieldPhoto(String uuid) async {
    try {
      final r = await dio.get<List<int>>(
        '/field/photos/$uuid',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      return r.data ?? const [];
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  // -------------------------------------------------------------------------
  // Oper (handover) — move a running log to a colleague with a 6-digit code
  // -------------------------------------------------------------------------

  static String _handoverBase(String entity) =>
      entity == 'drill_log' ? '/field/drill-logs' : '/field/castings';

  /// Ask the server for a single-use handover code (holder only, 15 minutes).
  Future<({String code, int validMinutes})> handoverCode(String entity, String uuid) async {
    try {
      final r = await dio.post<Map<String, dynamic>>('${_handoverBase(entity)}/$uuid/handover-code');
      final data = (r.data ?? const {}).cast<String, Object?>();
      return (code: '${data['code']}', validMinutes: toIntOrNull(data['validMinutes']) ?? 15);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Redeem a handover code: the log moves to THIS user, and the reply carries
  /// the whole body exactly as a phone stores it ([AppDatabase.saveSyncedDocument]).
  Future<({String uuid, int version, Map<String, Object?> body})> redeemHandover(
      String entity, String uuid, String code) async {
    try {
      final r = await dio.post<Map<String, dynamic>>(
        '${_handoverBase(entity)}/handover',
        data: {'uuid': uuid, 'code': code},
      );
      final data = (r.data ?? const {}).cast<String, Object?>();
      return (
        uuid: '${data['uuid']}',
        version: toIntOrNull(data['version']) ?? 1,
        body: (data['body'] as Map).cast<String, Object?>(),
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Ask the HOLDER to hand this log over. No code is involved: the holder's
  /// phone raises a notification on its next pull and answers from there.
  Future<void> requestHandover(String entity, String uuid) async {
    try {
      await dio.post<Map<String, dynamic>>('${_handoverBase(entity)}/$uuid/minta-oper');
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Holder's answer. [agree] true moves the log to the requester THERE AND
  /// THEN — no code, because the person tapping is the holder.
  Future<void> answerHandover(String entity, String uuid, {required bool agree}) async {
    try {
      await dio.post<Map<String, dynamic>>(
        '${_handoverBase(entity)}/$uuid/jawab-oper',
        data: {'setuju': agree},
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Riwayat satu titik, langsung dari server: SELURUH log cornya (termasuk
  /// yang sudah dihapus), TM-nya, hitungannya, dan jejak siapa mengubah apa.
  ///
  /// Dibaca dari server, bukan dari HP ini, justru karena yang ditanyakan
  /// adalah titik yang dikerjakan HP LAIN — lognya memang tidak pernah ada
  /// di sini.
  Future<Map<String, Object?>> pointHistory(int pileId) async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/field/pile-points/$pileId/riwayat');
      return (r.data ?? const {}).cast<String, Object?>();
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Daftarkan token FCM HP ini atas nama pengguna yang sedang masuk.
  ///
  /// Dipanggil saat masuk, saat aplikasi dibuka, dan setiap kali Firebase
  /// MEMUTAR tokennya sendiri. Aman diulang: server memperbarui baris yang
  /// tokennya sama, bukan menggandakannya.
  Future<void> registerPushToken({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    try {
      await dio.post<Map<String, dynamic>>(
        '/device-tokens/register',
        data: {
          'token': token,
          'platform': platform,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'appVersion': appVersion,
        },
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Cabut token HP ini — dipanggil SEBELUM `logout()`.
  ///
  /// Urutannya penting: `logout()` mencabut refresh token, dan sesudah itu
  /// panggilan ini tidak punya izin lagi. Kalau tidak dicabut, HP yang
  /// sudah berganti pemegang tetap menerima kabar untuk pemegang
  /// sebelumnya sampai ada orang lain yang masuk di HP itu.
  Future<void> unregisterPushToken(String token) async {
    try {
      await dio.post<Map<String, dynamic>>(
        '/device-tokens/unregister',
        data: {'token': token},
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> logout() async {
    final refresh = await session.refreshToken();
    if (refresh == null) return;
    try {
      await dio.post<dynamic>('/auth/logout', options: Options(headers: {'x-refresh-token': 'Bearer $refresh'}));
    } catch (_) {
      // Logout still happens on the phone even if the server is unreachable.
    }
  }
}
