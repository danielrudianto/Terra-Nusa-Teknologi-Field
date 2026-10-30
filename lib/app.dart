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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
