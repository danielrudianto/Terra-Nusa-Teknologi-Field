import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../konteks.dart';

const _tugasSinkron = 'sinkron-lapangan';
const _namaBerkala = 'sinkron-berkala';
const _namaSegera = 'sinkron-segera';

/// Titik masuk mesin Flutter LATAR (workmanager).
///
/// Berjalan di isolate dan mesin yang terpisah dari layar — tanpa
/// MainActivity, tanpa ProviderScope. Karena itu ia merakit sendiri
/// semuanya lewat [KonteksAplikasi.buka], sama persis dengan `main()`.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((tugas, data) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final konteks = await KonteksAplikasi.buka();
    try {
      final hasil = await konteks.mesin.jalankan();
      debugPrint('Sinkron latar ($tugas): $hasil');
      // `false` = minta workmanager mengulang dengan jedanya sendiri.
      // Hanya untuk masalah sementara; sesi habis menunggu mandor masuk
      // lagi, dan mengulang tidak akan mengubahnya.
      return !(hasil.tanpaJaringan || (hasil.galat != null && !hasil.sesiHabis));
    } catch (e) {
      debugPrint('Sinkron latar gagal: $e');
      return false;
    } finally {
      await konteks.tutup();
    }
  });
}

/// Sekali saat aplikasi dibuka. Berkala 15 menit — batas bawah Android.
Future<void> pasangSinkronLatar() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _namaBerkala,
    _tugasSinkron,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 1),
  );
}

/// Sesudah menyimpan dokumen: kirim SEGERA begitu ada sinyal, walau
/// aplikasinya ditutup. Bila sinyal sedang ada, layar sudah mengirim
/// sendiri lebih dulu; tugas ini jaring pengamannya.
Future<void> mintaSinkronSegera() => Workmanager().registerOneOffTask(
      _namaSegera,
      _tugasSinkron,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );

Future<void> hentikanSinkronLatar() => Workmanager().cancelAll();
