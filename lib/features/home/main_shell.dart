import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/features.dart';
import '../../core/providers.dart';

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
    // 2 Cor, 3 Antrean); a hidden tab is only left out of the bar.
    final shown = [0, if (Features.attendance) 1, 2, 3];
    final selected = shown.indexOf(shell.currentIndex);
    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: (i) => shell.goBranch(shown[i], initialLocation: shown[i] == shell.currentIndex),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
            if (Features.attendance)
              const NavigationDestination(
                icon: Icon(Icons.how_to_reg_outlined),
                selectedIcon: Icon(Icons.how_to_reg),
                label: 'Absensi',
              ),
            const NavigationDestination(
              icon: Icon(Icons.foundation_outlined),
              selectedIcon: Icon(Icons.foundation),
              label: 'Cor',
            ),
            NavigationDestination(
              icon: badge(Icons.cloud_upload_outlined),
              selectedIcon: badge(Icons.cloud_upload),
              label: 'Antrean',
            ),
          ],
        ),
      ),
    );
  }
}
