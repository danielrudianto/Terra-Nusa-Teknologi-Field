import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_context.dart';
import 'core/config/env.dart';
import 'core/providers.dart';
import 'core/device/aksi_notifikasi.dart';
import 'core/device/notifications.dart';
import 'core/sync/background_sync.dart';
import 'core/util/app_log.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.installErrorHandlers();
  await initializeDateFormatting('id');

  final appContext = await AppContext.open();
  final container = ProviderContainer(overrides: [appContextProvider.overrideWithValue(appContext)]);

  // Refresh token rejected mid-use → "Masuk lagi" (sign in again) banner.
  appContext.api.onSessionExpired = () => container.read(sessionProvider.notifier).markExpired();

  await Notifications.init(
    (payload, action) {
      // "Selesai TM" dari arloji sudah dikerjakan di isolate latar; yang
      // sampai ke sini hanya ketukan yang memang meminta layarnya dibuka.
      if (action == Notifications.actionFinishNow) return;
      if (payload != null && payload.startsWith('/')) container.read(routerProvider).go(payload);
    },
    diLatar: tanganiAksiNotifikasiLatar,
  );
  final initialRoute = await Notifications.initialRoute();

  try {
    await setupBackgroundSync();
  } catch (e, st) {
    // Without background sync the app still runs; push manually from the screen.
    AppLog.error('background', 'not registered: $e', st);
  }
  AppLog.info('app', 'start v${Env.appVersion}');

  runApp(UncontrolledProviderScope(container: container, child: const FieldApp()));

  if (initialRoute != null && initialRoute.startsWith('/')) {
    WidgetsBinding.instance.addPostFrameCallback((_) => container.read(routerProvider).go(initialRoute));
  }
}
