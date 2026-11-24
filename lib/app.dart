import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/device/pesan_awan.dart';
import 'core/device/reminder_rearm.dart';
import 'core/i18n.dart';
import 'core/providers.dart';
import 'core/theme/appearance.dart';
import 'core/theme/theme.dart';
import 'features/settings/power_guide.dart';
import 'features/update/update_required_page.dart';
import 'router.dart';

class FieldApp extends ConsumerStatefulWidget {
  const FieldApp({super.key});

  @override
  ConsumerState<FieldApp> createState() => _FieldAppState();
}

class _FieldAppState extends ConsumerState<FieldApp> with WidgetsBindingObserver {
  /// Pull on a timer WHILE THE APP IS OPEN.
  ///
  /// Reported by Daniel, 22 Nov 2026: "Dari kantor delete log, dari hp ga ke
  /// refresh harus manual". The background worker only runs every 15
  /// minutes — Android's lower bound — and otherwise the phone only pulls
  /// when something is saved or the app comes back to the front. Someone
  /// standing at the hole with the screen open, waiting for a truck, does
  /// neither.
  ///
  /// One minute: office changes arrive while the person is still holding
  /// the phone, without loading the site's signal. Never in the background
  /// (see [_pullWhileOpen]); the 15-minute worker keeps that job.
  static const _pullEvery = Duration(minutes: 1);
  Timer? _pullTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pullTimer = Timer.periodic(_pullEvery, (_) => _pullWhileOpen());
    // Cold start: once the stored session is read, fetch its permissions
    // again — see [_reloadPermissions].
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final s = await ref.read(sessionProvider.future);
        if (mounted && s.isLoggedIn) _reloadPermissions();
      } catch (_) {
        // No stored session yet: the login reads permissions itself.
      }
    });
  }

  @override
  void dispose() {
    _pullTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Only when the screen is actually visible and someone is signed in. A
  /// sync already running is not doubled (`SyncNotifier.run`).
  void _pullWhileOpen() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!(ref.read(sessionProvider).value?.isLoggedIn ?? false)) return;
    unawaited(ref.read(syncProvider.notifier).run());
  }

  /// PERMISSIONS ARE READ AGAIN on every start and return to the app
  /// (24 Nov 2026). They used to be read only at login, so a module added
  /// later — IPL, 23 Nov — stayed invisible on a phone that logged in
  /// before it existed: Ko Michael, level 5, saw no IPL entry until he
  /// tapped "Muat ulang hak akses" in Settings. No signal = the last known
  /// permissions stay (see [SessionNotifier.reloadPermissions]).
  void _reloadPermissions() {
    unawaited(ref.read(sessionProvider.notifier).reloadPermissions().catchError((_) {}));
  }

  /// Returning to the app = a good moment to push: the foreman has just
  /// picked up the phone, so there may be signal by now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (ref.read(sessionProvider).value?.isLoggedIn ?? false)) {
      ref.read(syncProvider.notifier).run();
      // Alarms do not survive a reboot or an app update, and nothing tells
      // the foreman when they vanish. Putting them back on every resume is
      // cheap and idempotent — see [rearmReminders].
      final me = ref.read(userProvider);
      if (me != null) {
        unawaited(rearmReminders(db: ref.read(dbProvider), userId: me.id).catchError((_) {}));
      }
      // Sama alasannya dengan pengingat di atas: murah, idempoten, dan
      // satu-satunya kesempatan memperbaiki pendaftaran token yang gagal
      // karena HP-nya tanpa sinyal saat aplikasi dibuka.
      unawaited(PesanAwan.pastikanTerdaftar(ref.read(apiProvider)));
      _reloadPermissions();
    }
    // Back from the phone's settings: read battery saving again.
    if (state == AppLifecycleState.resumed) ref.invalidate(powerStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final look = ref.watch(appearanceProvider).value ?? const Appearance();
    return MaterialApp.router(
      title: 'TerraBot Field',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, accent: look.accent),
      darkTheme: buildTheme(Brightness.dark, accent: look.accent),
      themeMode: look.mode,
      routerConfig: ref.watch(routerProvider),
      // null = follow the phone; AppLocalizations falls back to Indonesian
      // for a language the app does not speak.
      locale: look.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      // A version the server no longer serves gets the update page instead
      // of the app — on every screen, without touching the routes.
      builder: (context, child) {
        // Remembered for code with no widget tree (notifications, the
        // background worker): see [L10n].
        L10n.remember(t(context));
        final outdated = ref.watch(appOutdatedProvider).value;
        final body = outdated == null ? child! : UpdateRequiredPage(info: outdated);
        // Text size from Pengaturan → Tampilan. The phone's own
        // accessibility setting still counts: whichever is LARGER wins,
        // so the app never shrinks text below what the phone asks for.
        final scale = look.textScale;
        final sized = scale == 1.0
            ? body
            : Builder(
                builder: (context) {
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: scale, maxScaleFactor: 3.0)),
                    child: body,
                  );
                },
              );
        return _OrientationPolicy(child: sized);
      },
    );
  }
}


/// Portrait on a phone, free on a big screen.
///
/// A phone laid flat on the hopper rotated the whole log into landscape,
/// where every form becomes two columns of nothing — the app is held in one
/// hand, with the other on the tremie.
///
/// It is NOT locked in the manifest. 600dp is Android's own phone/tablet
/// line, and it is the line a folding phone crosses when it opens: locked
/// while closed, free once unfolded, decided again every time the window
/// changes size. A manifest lock could not tell those apart — and from
/// Android 16 the system ignores orientation locks on large screens anyway,
/// so it would be both wrong and useless.
class _OrientationPolicy extends StatefulWidget {
  const _OrientationPolicy({required this.child});

  final Widget child;

  @override
  State<_OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<_OrientationPolicy> {
  bool? _portraitOnly;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final phone = MediaQuery.sizeOf(context).shortestSide < 600;
    // Only when the answer CHANGES: this runs on every metrics change,
    // including each frame of a fold animation.
    if (phone == _portraitOnly) return;
    _portraitOnly = phone;
    unawaited(SystemChrome.setPreferredOrientations(
      phone ? const [DeviceOrientation.portraitUp] : DeviceOrientation.values,
    ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
