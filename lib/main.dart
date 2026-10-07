import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'inti/konteks.dart';
import 'inti/penyedia.dart';
import 'inti/perangkat/notifikasi.dart';
import 'inti/sinkron/pekerja_latar.dart';
import 'rute.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id');

  final konteks = await KonteksAplikasi.buka();
  final wadah = ProviderContainer(overrides: [konteksProvider.overrideWithValue(konteks)]);

  // Refresh token ditolak di tengah pemakaian → banner "Masuk lagi".
  konteks.api.padaSesiHabis = () => wadah.read(sesiProvider.notifier).tandaiHabis();

  await Notifikasi.siapkan((payload, aksi) {
    if (payload != null && payload.startsWith('/')) wadah.read(ruteProvider).go(payload);
  });
  final ruteAwal = await Notifikasi.ruteAwal();

  try {
    await pasangSinkronLatar();
  } catch (e) {
    // Tanpa sinkron latar aplikasi tetap jalan; kirim manual dari layar.
    debugPrint('Sinkron latar tidak terpasang: $e');
  }

  runApp(UncontrolledProviderScope(container: wadah, child: const AplikasiField()));

  if (ruteAwal != null && ruteAwal.startsWith('/')) {
    WidgetsBinding.instance.addPostFrameCallback((_) => wadah.read(ruteProvider).go(ruteAwal));
  }
}
