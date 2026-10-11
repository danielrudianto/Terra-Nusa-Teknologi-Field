import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      locale: const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // A version the server no longer serves gets the update page instead
      // of the app — on every screen, without touching the routes.
      builder: (context, child) {
        final outdated = ref.watch(appOutdatedProvider).value;
        final body = outdated == null ? child! : UpdateRequiredPage(info: outdated);
        // Text size from Pengaturan → Tampilan. The phone's own
        // accessibility setting still counts: whichever is LARGER wins,
        // so the app never shrinks text below what the phone asks for.
        final scale = look.textScale;
        if (scale == 1.0) return body;
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: scale, maxScaleFactor: 3.0)),
          child: body,
        );
      },
    );
  }
}
