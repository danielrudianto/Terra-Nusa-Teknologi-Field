import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/features.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../core/theme/dimens.dart';
import '../../core/theme/motion.dart';

/// Shell with bottom navigation. The badge on the Queue tab = the number of
/// documents + photos not yet pushed, so the foreman knows without opening
/// anything.
///
/// Back on Cor, Antrean or Pengaturan goes to Beranda instead of closing the
/// app: those tabs are often opened from a Beranda shortcut, and a user
/// expects back to undo that, not to drop them on the phone's home screen.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  /// Branch index in the router ← → position in the bar.
  ///
  /// The router's branch order is FIXED (0 Beranda, 1 Absensi, 2 Cor,
  /// 3 Antrean, 4 Pengaturan) because a branch index is what `goBranch` takes
  /// and what `currentIndex` returns. The bar shows a subset of it, so the two
  /// numbers are NOT the same and must never be used interchangeably — the
  /// previous version of this file tracked them in a list literal and a
  /// sentinel `-1`, which is exactly the shape that goes wrong when a tab is
  /// added or removed.
  ///
  /// Absensi is absent here, not greyed out. On hold since 9 Oct 2026 and with
  /// no decision yet (Daniel, 15 Okt 2026), an inert tab was answering a
  /// question nobody was asking while taking a quarter of the bar; flipping
  /// [Features.attendance] back to `true` puts it back in place.
  static List<int> _branches() => [
        0,
        if (Features.attendance) 1,
        2,
        3,
        4,
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = (ref.watch(pendingCountProvider).value ?? 0) +
        (ref.watch(pendingPhotoCountProvider).value ?? 0);
    final branches = _branches();
    final onHome = shell.currentIndex == 0;
    // A branch the bar does not show (Absensi while it is off) leaves nothing
    // to highlight; Beranda is the honest fallback rather than a wrong tab
    // drawn as selected.
    final selected = branches.indexOf(shell.currentIndex);

    return PopScope(
      canPop: onHome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        // The branch bodies live in an IndexedStack, which swaps instantly.
        // A tap on a tab is the most frequent gesture in the app, so it gets
        // the one piece of motion that says "this is a sibling screen, not a
        // deeper one": a lateral slide, direction following the tap.
        body: TabSwap(index: shell.currentIndex, child: shell),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: (i) => shell.goBranch(
            branches[i],
            initialLocation: branches[i] == shell.currentIndex,
          ),
          destinations: [
            for (final b in branches) _destination(context, b, pending),
          ],
        ),
      ),
    );
  }

  NavigationDestination _destination(BuildContext context, int branch, int pending) {
    switch (branch) {
      case 0:
        return NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: t(context).navHome,
        );
      case 1:
        return NavigationDestination(
          icon: const Icon(Icons.how_to_reg_outlined),
          selectedIcon: const Icon(Icons.how_to_reg),
          label: t(context).navAttendance,
        );
      case 2:
        return NavigationDestination(
          icon: const Icon(Icons.foundation_outlined),
          selectedIcon: const Icon(Icons.foundation),
          label: t(context).navCasting,
        );
      case 3:
        // The count GROWS while the phone is offline and drops to nothing the
        // moment a sync lands. Both are news, so the badge animates in and
        // out instead of blinking into a different number.
        return NavigationDestination(
          icon: _QueueIcon(Icons.cloud_upload_outlined, pending),
          selectedIcon: _QueueIcon(Icons.cloud_upload, pending),
          label: t(context).navQueue,
        );
      default:
        return NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: t(context).navSettings,
        );
    }
  }
}

/// Queue icon with the unsent count on it.
///
/// `Badge` itself has no entrance, so an item queued while the user is looking
/// at the bar makes the number appear out of nothing. Scaling it in from the
/// icon reads as "one more thing is waiting" — and scaling it out, as "sent".
class _QueueIcon extends StatelessWidget {
  const _QueueIcon(this.icon, this.pending);

  final IconData icon;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: pending > 0,
      // Fade, NOT the rolling figure used on the big numbers: the badge is
      // barely wider than its digits, and anything that slides inside it is
      // clipped halfway through the move.
      label: AnimatedSwitcher(
        duration: Dimens.motionFast,
        child: Text(
          pending > 99 ? '99+' : '$pending',
          key: ValueKey(pending),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      child: AnimatedScale(
        // A barely-there swell when the first item lands; the icon itself
        // must stay exactly where the thumb expects it.
        scale: pending > 0 ? 1.06 : 1,
        duration: Dimens.motionMedium,
        curve: Curves.easeOutBack,
        child: Icon(icon),
      ),
    );
  }
}
