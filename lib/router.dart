import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/attendance/attendance_form.dart';
import 'features/attendance/attendance_page.dart';
import 'features/queue/queue_page.dart';
import 'features/home/home_page.dart';
import 'features/home/main_shell.dart';
import 'features/login/login_page.dart';
import 'features/workers/worker_form.dart';
import 'features/workers/workers_page.dart';
import 'features/settings/settings_page.dart';
import 'features/casting/casting_form.dart';
import 'features/casting/casting_page.dart';
import 'features/casting/pile_points_page.dart';
import 'features/casting/point_history_page.dart';
import 'features/drilling/drill_log_page.dart';
import 'features/reports/report_page.dart';
import 'core/config/features.dart';
import 'core/providers.dart';

/// Route map.
///
///   /login
///   /home                         ┐
///   /attendance                   │ shell with bottom navigation
///   /casting                      │
///   /queue                        ┘
///   /attendance/new?project=ID    new attendance form
///   /attendance/:uuid             open attendance
///   /workers                      all workers, filterable by project
///   /workers/new?project=ID       register (project prefilled, optional)
///   /workers/:uuid
///   /casting/project/:id          pile points of one project
///   /casting/log/:uuid            casting log (new or continued)
///   /casting/point/:id/history    server-side history of one pile point
///   /drilling/log/:uuid           drill log (new or continued)
///   /reports                      daily drilling & casting report (directors)
///   /settings
final routerProvider = Provider<GoRouter>((ref) {
  final flags = _SessionListenable(ref);
  final router = GoRouter(
    initialLocation: '/home',
    refreshListenable: flags,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      if (session.isLoading && !session.hasValue) return null;
      final user = session.value?.user;
      final toLogin = state.matchedLocation == '/login';
      // An EXPIRED session may still open the app: its documents are on the phone and
      // can still be viewed/filled in. All that is asked is to log in again in order to
      // push — via a banner, not by closing off every screen.
      if (user == null) return toLogin ? null : '/login';
      // Satu akun, satu HP: HP yang sudah digantikan HP lain punya sesi yang
      // masih SAH — tokennya belum kedaluwarsa, yang dikunci ada di server.
      // Tanpa syarat kunci ini, tombol "Masuk di HP ini" pada banner melempar
      // ke /login lalu DIPANTULKAN kembali ke /home, sehingga banner itu tidak
      // bisa diapa-apakan sama sekali dan HP-nya mentok di situ.
      final locked = ref.read(deviceLockProvider).value != null;
      if (toLogin && !(session.value?.sessionExpired ?? false) && !locked) return '/home';
      // Attendance on hold: its screens cannot be reached, even from an old
      // notification or a queue entry.
      if (!Features.attendance) {
        final at = state.matchedLocation;
        if (at.startsWith('/attendance') || at.startsWith('/workers')) return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/attendance', builder: (_, _) => const AttendancePage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/casting', builder: (_, _) => const CastingPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/queue', builder: (_, _) => const QueuePage())]),
        ],
      ),
      GoRoute(
        path: '/attendance/new',
        builder: (_, s) => AttendanceForm(uuid: null, projectId: int.tryParse(s.uri.queryParameters['project'] ?? '')),
      ),
      GoRoute(path: '/attendance/:uuid', builder: (_, s) => AttendanceForm(uuid: s.pathParameters['uuid'])),
      GoRoute(path: '/workers', builder: (_, _) => const WorkersPage()),
      GoRoute(
        path: '/workers/new',
        builder: (_, s) => WorkerForm(uuid: null, projectId: int.tryParse(s.uri.queryParameters['project'] ?? '')),
      ),
      GoRoute(path: '/workers/:uuid', builder: (_, s) => WorkerForm(uuid: s.pathParameters['uuid'])),
      GoRoute(
        path: '/casting/project/:id',
        builder: (_, s) => PilePointsPage(projectId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/casting/log/:uuid',
        builder: (_, s) => CastingForm(uuid: s.pathParameters['uuid']!, pilePointUuid: s.uri.queryParameters['pilePoint']),
      ),
      GoRoute(
        path: '/drilling/log/:uuid',
        builder: (_, s) => DrillLogPage(uuid: s.pathParameters['uuid']!, pilePointUuid: s.uri.queryParameters['pilePoint']),
      ),
      GoRoute(
        path: '/casting/point/:id/history',
        builder: (_, s) => PointHistoryPage(
          pileId: int.parse(s.pathParameters['id']!),
          code: s.uri.queryParameters['code'] ?? '',
        ),
      ),
      GoRoute(path: '/reports', builder: (_, _) => const ReportPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    ],
  );
  ref.onDispose(() {
    flags.dispose();
    router.dispose();
  });
  return router;
});

class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    _session = ref.listen(sessionProvider, (_, _) => notifyListeners());
    // Kunci perangkat ikut didengar: redirect di atas membacanya, jadi kalau
    // perubahannya tidak memicu penilaian ulang, rute akan memakai nilai lama.
    _lock = ref.listen(deviceLockProvider, (_, _) => notifyListeners());
  }

  late final ProviderSubscription<Object?> _session;
  late final ProviderSubscription<Object?> _lock;

  @override
  void dispose() {
    _session.close();
    _lock.close();
    super.dispose();
  }
}
