import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../app_context.dart';

const _syncTaskName = 'field-sync';
const _periodicName = 'field-sync-periodic';
const _immediateName = 'field-sync-now';

/// Entry point of the BACKGROUND Flutter engine (workmanager).
///
/// Runs in an isolate and engine separate from the screen — with no
/// MainActivity and no ProviderScope. That is why it assembles everything itself
/// via [AppContext.open], exactly the same as `main()`.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, data) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final appContext = await AppContext.open();
    try {
      final result = await appContext.engine.run();
      debugPrint('Background sync ($task): $result');
      // `false` = ask workmanager to retry with its own delay.
      // Only for transient problems; an expired session waits for the foreman to sign
      // in again, and retrying will not change that.
      return !(result.offline || (result.error != null && !result.sessionExpired));
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return false;
    } finally {
      await appContext.close();
    }
  });
}

/// Once when the app is opened. Periodic every 15 minutes — Android's lower bound.
Future<void> setupBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicName,
    _syncTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 1),
  );
}

/// After saving a document: push IMMEDIATELY once there is signal, even if
/// the app is closed. If there is signal right now, the screen has already pushed
/// by itself first; this task is the safety net.
Future<void> requestImmediateSync() => Workmanager().registerOneOffTask(
      _immediateName,
      _syncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
    );

Future<void> stopBackgroundSync() => Workmanager().cancelAll();
