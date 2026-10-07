import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitur/absensi/form_absen.dart';
import 'fitur/absensi/halaman_absensi.dart';
import 'fitur/antrean/halaman_antrean.dart';
import 'fitur/beranda/halaman_beranda.dart';
import 'fitur/beranda/kerangka.dart';
import 'fitur/masuk/halaman_masuk.dart';
import 'fitur/pekerja/form_pekerja.dart';
import 'fitur/pekerja/halaman_pekerja.dart';
import 'fitur/pengaturan/halaman_pengaturan.dart';
import 'fitur/pengecoran/form_cor.dart';
import 'fitur/pengecoran/halaman_pengecoran.dart';
import 'fitur/pengecoran/halaman_titik.dart';
import 'inti/penyedia.dart';

/// Peta rute.
///
///   /masuk
///   /beranda                      ┐
///   /absensi                      │ kerangka dengan navigasi bawah
///   /pengecoran                   │
///   /antrean                      ┘
///   /absensi/baru?proyek=ID       form absen baru
///   /absensi/:uuid                buka absen
///   /pekerja                      daftar kru
///   /pekerja/baru, /pekerja/:uuid
///   /pengecoran/proyek/:id        titik bor satu proyek
///   /pengecoran/cor/:uuid         log cor (baru atau lanjutan)
///   /pengaturan
final ruteProvider = Provider<GoRouter>((ref) {
  final penanda = _PenandaSesi(ref);
  final router = GoRouter(
    initialLocation: '/beranda',
    refreshListenable: penanda,
    redirect: (context, state) {
      final sesi = ref.read(sesiProvider);
      if (sesi.isLoading && !sesi.hasValue) return null;
      final pengguna = sesi.value?.pengguna;
      final keMasuk = state.matchedLocation == '/masuk';
      // Sesi HABIS tetap boleh membuka aplikasi: dokumennya ada di HP dan
      // tetap dapat dilihat/diisi. Yang diminta hanya masuk lagi untuk
      // mengirim — lewat banner, bukan dengan menutup semua layar.
      if (pengguna == null) return keMasuk ? null : '/masuk';
      if (keMasuk && !(sesi.value?.sesiHabis ?? false)) return '/beranda';
      return null;
    },
    routes: [
      GoRoute(path: '/masuk', builder: (_, __) => const HalamanMasuk()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => KerangkaUtama(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/beranda', builder: (_, __) => const HalamanBeranda())]),
          StatefulShellBranch(routes: [GoRoute(path: '/absensi', builder: (_, __) => const HalamanAbsensi())]),
          StatefulShellBranch(routes: [GoRoute(path: '/pengecoran', builder: (_, __) => const HalamanPengecoran())]),
          StatefulShellBranch(routes: [GoRoute(path: '/antrean', builder: (_, __) => const HalamanAntrean())]),
        ],
      ),
      GoRoute(
        path: '/absensi/baru',
        builder: (_, s) => FormAbsen(uuid: null, proyekId: int.tryParse(s.uri.queryParameters['proyek'] ?? '')),
      ),
      GoRoute(path: '/absensi/:uuid', builder: (_, s) => FormAbsen(uuid: s.pathParameters['uuid'])),
      GoRoute(path: '/pekerja', builder: (_, __) => const HalamanPekerja()),
      GoRoute(path: '/pekerja/baru', builder: (_, __) => const FormPekerja(uuid: null)),
      GoRoute(path: '/pekerja/:uuid', builder: (_, s) => FormPekerja(uuid: s.pathParameters['uuid'])),
      GoRoute(
        path: '/pengecoran/proyek/:id',
        builder: (_, s) => HalamanTitik(proyekId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/pengecoran/cor/:uuid',
        builder: (_, s) => FormCor(uuid: s.pathParameters['uuid']!, titikUuid: s.uri.queryParameters['titik']),
      ),
      GoRoute(path: '/pengaturan', builder: (_, __) => const HalamanPengaturan()),
    ],
  );
  ref.onDispose(() {
    penanda.dispose();
    router.dispose();
  });
  return router;
});

class _PenandaSesi extends ChangeNotifier {
  _PenandaSesi(Ref ref) {
    _langganan = ref.listen(sesiProvider, (_, __) => notifyListeners());
  }

  late final ProviderSubscription<Object?> _langganan;

  @override
  void dispose() {
    _langganan.close();
    super.dispose();
  }
}
