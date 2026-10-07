import 'dart:async';

import 'package:dio/dio.dart';

import '../db/database.dart';
import '../konfigurasi/env.dart';
import '../sesi/sesi.dart';
import '../util/format.dart';
import 'galat.dart';

/// Klien HTTP ke backend TerraBot.
///
/// PENYEGARAN TOKEN — SATU SAJA, DI SELURUH APLIKASI
///
/// Refresh token TerraBot hanya berlaku SEKALI. Dua penyegaran serentak
/// dengan token yang sama dibaca server sebagai token yang dicuri, dan
/// SELURUH sesinya dicabut. Di HP, dua penyegaran serentak itu mudah
/// terjadi: layar dan pekerja latar (workmanager) berjalan di isolate
/// berbeda, dan keduanya dapat menerima 401 pada saat yang sama.
///
/// Karena itu penyegaran memakai kunci lintas-isolate di basis data lokal,
/// dan sebelum menyegarkan, token yang tersimpan diperiksa ulang: bila
/// sudah berbeda dari yang ditolak, isolate lain baru saja menyegarkannya
/// dan yang ini cukup memakai hasilnya.
class KlienApi {
  KlienApi({required this.db, required this.sesi, required this.idPerangkat}) {
    dio = Dio(
      BaseOptions(
        baseUrl: Env.apiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
        headers: {'X-Device-Id': idPerangkat, 'X-App-Version': Env.versiAplikasi, 'X-Os-Version': 'android'},
      ),
    );
    dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (opsi, lanjut) async {
          final akses = await sesi.aksesToken();
          if (akses != null && !opsi.path.startsWith('/auth/')) {
            opsi.headers['Authorization'] = 'Bearer $akses';
          }
          lanjut.next(opsi);
        },
        onError: (galat, lanjut) async {
          final opsi = galat.requestOptions;
          final sudahDiulang = opsi.extra['diulang'] == true;
          if (galat.response?.statusCode != 401 || sudahDiulang || opsi.path.startsWith('/auth/')) {
            return lanjut.next(galat);
          }
          final ditolak = (opsi.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
          final berhasil = await _segarkan(ditolak);
          if (!berhasil) return lanjut.next(galat);
          try {
            final baru = await sesi.aksesToken();
            opsi.headers['Authorization'] = 'Bearer $baru';
            opsi.extra['diulang'] = true;
            lanjut.resolve(await dio.fetch<dynamic>(opsi));
          } on DioException catch (e) {
            lanjut.next(e);
          }
        },
      ),
    );
  }

  final BasisData db;
  final PenyimpanSesi sesi;
  final String idPerangkat;
  late final Dio dio;

  /// Dipanggil saat refresh token ditolak (sesi benar-benar habis).
  void Function()? padaSesiHabis;

  Future<bool> _segarkan(String? aksesDitolak) async {
    final pemilik = uuidBaru();
    var dapat = false;
    for (var i = 0; i < 40 && !dapat; i++) {
      dapat = await db.ambilKunci('token', pemilik, const Duration(seconds: 30));
      if (!dapat) await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    try {
      // Isolate lain sudah menyegarkan selama kita menunggu?
      final kini = await sesi.aksesToken();
      if (kini != null && kini != aksesDitolak) return true;
      if (!dapat) return false;

      final segar = await sesi.segarToken();
      if (segar == null) {
        await _habis();
        return false;
      }
      final polos = Dio(BaseOptions(baseUrl: Env.apiUrl, connectTimeout: const Duration(seconds: 15)));
      final r = await polos.post<Map<String, dynamic>>(
        '/auth/refresh',
        options: Options(headers: {
          // Header, bukan cookie: aplikasi native tidak punya wadah cookie
          // peramban. Jalur ini PERMANEN di server (lihat auth_routes.py).
          'x-refresh-token': 'Bearer $segar',
          'X-Device-Id': idPerangkat,
          'X-App-Version': Env.versiAplikasi,
        }),
      );
      final data = r.data ?? const {};
      final akses = data['access_token'] as String?;
      final segarBaru = data['refresh_token'] as String?;
      if (akses == null || segarBaru == null) return false;
      await sesi.tulisToken(akses, segarBaru);
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await _habis();
      // Tanpa sinyal: bukan sesi habis. Dicoba lagi pada kiriman berikutnya.
      return false;
    } finally {
      if (dapat) await db.lepasKunci('token', pemilik);
    }
  }

  Future<void> _habis() async {
    await sesi.tandaiSesiHabis();
    padaSesiHabis?.call();
  }

  // -------------------------------------------------------------------------

  Future<(Pengguna, String, String)> masuk(String email, String sandi) async {
    try {
      final r = await dio.post<Map<String, dynamic>>('/auth/', data: {'email': email.trim(), 'password': sandi});
      final data = r.data ?? const {};
      final pengguna = Pengguna.dariJson((data['user'] as Map).cast<String, Object?>());
      return (pengguna, data['access_token'] as String, data['refresh_token'] as String);
    } catch (e) {
      throw GalatApi.dari(e);
    }
  }

  Future<PetaIzin> izin() async {
    try {
      final r = await dio.get<Map<String, dynamic>>('/permissions/me');
      return PetaIzin.dariJson((r.data ?? const {}).cast<String, Object?>());
    } catch (e) {
      throw GalatApi.dari(e);
    }
  }

  Future<void> keluar() async {
    final segar = await sesi.segarToken();
    if (segar == null) return;
    try {
      await dio.post<dynamic>('/auth/logout', options: Options(headers: {'x-refresh-token': 'Bearer $segar'}));
    } catch (_) {
      // Keluar tetap terjadi di HP walau server tidak terjangkau.
    }
  }
}
