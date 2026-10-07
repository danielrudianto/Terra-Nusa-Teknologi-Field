import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inti/penyedia.dart';
import 'inti/tema/tema.dart';
import 'rute.dart';

class AplikasiField extends ConsumerStatefulWidget {
  const AplikasiField({super.key});

  @override
  ConsumerState<AplikasiField> createState() => _AplikasiFieldState();
}

class _AplikasiFieldState extends ConsumerState<AplikasiField> with WidgetsBindingObserver {
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

  /// Kembali ke aplikasi = saat yang baik untuk mengirim: mandor baru
  /// saja memegang HP-nya, sinyal mungkin sudah ada.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (ref.read(sesiProvider).value?.masuk ?? false)) {
      ref.read(sinkronProvider.notifier).jalankan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TerraBot Field',
      debugShowCheckedModeBanner: false,
      theme: buatTema(Brightness.light),
      darkTheme: buatTema(Brightness.dark),
      routerConfig: ref.watch(ruteProvider),
      locale: const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
