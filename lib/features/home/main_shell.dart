import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/features.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/color_tokens.dart';
import '../../core/widgets/app_snack.dart';

/// Shell with bottom navigation. The badge on the Queue tab = the number of documents
/// + photos not yet pushed, so the foreman knows without opening anything.
///
/// Back on Absensi, Cor or Antrean goes to Beranda instead of closing the
/// app: those tabs are often opened from a Beranda shortcut, and a user
/// expects back to undo that, not to drop them on the phone's home screen.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = (ref.watch(pendingCountProvider).value ?? 0) +
        (ref.watch(pendingPhotoCountProvider).value ?? 0);
    Widget badge(IconData icon) =>
        Badge(isLabelVisible: pending > 0, label: Text(pending > 99 ? '99+' : '$pending'), child: Icon(icon));
    final onHome = shell.currentIndex == 0;
    // Branch indexes stay as the router declares them (0 Beranda, 1 Absensi,
    // 2 Cor, 3 Antrean). While attendance is on hold its tab stays in the bar
    // but greyed out and inert (-1): three tabs looked like an app missing
    // something, and a visible "coming soon" answers the question before
    // anyone asks it.
    final shown = [0, if (Features.attendance) 1 else -1, 2, 3];
    final selected = shown.indexOf(shell.currentIndex);
    final w = context.colors;
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: (i) {
            // The disabled tab never navigates; the selection stays where it is.
            if (shown[i] < 0) {
              showSnack(context, t(context).navAttendanceSoon, icon: Icons.hourglass_empty);
              return;
            }
            shell.goBranch(shown[i], initialLocation: shown[i] == shell.currentIndex);
          },
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: t(context).navHome),
            if (Features.attendance)
              NavigationDestination(
                icon: const Icon(Icons.how_to_reg_outlined),
                selectedIcon: const Icon(Icons.how_to_reg),
                label: t(context).navAttendance,
              )
            else
              NavigationDestination(
                icon: Icon(Icons.how_to_reg_outlined, color: w.faint),
                label: t(context).navAttendance,
                tooltip: t(context).comingSoon,
              ),
            NavigationDestination(
              icon: const Icon(Icons.foundation_outlined),
              selectedIcon: const Icon(Icons.foundation),
              label: t(context).navCasting,
            ),
            NavigationDestination(
              icon: badge(Icons.cloud_upload_outlined),
              selectedIcon: badge(Icons.cloud_upload),
              label: t(context).navQueue,
            ),
          ],
        ),
      ),
    );
  }
}
