import 'package:flutter/material.dart';

import 'app_snack.dart';

/// A control that is deliberately DEAD, wrapped so that pressing it still
/// answers "why".
///
/// A disabled button on its own teaches nothing. The finger lands, nothing
/// moves, and the person decides either that the phone is broken or that they
/// did something wrong — and the one thing they will not do is work out, from
/// a greyed-out rectangle, which of five conditions is the one holding them
/// up. On this app that matters more than usual: the people filling these
/// screens are standing next to a running rig, in the sun, and whatever the
/// app will not explain becomes a phone call to the office.
///
/// So BOTH things happen. The control stays disabled, because that is what
/// keeps wrong data out of the log; and the press is caught here and answered
/// in one sentence that names what is missing.
///
/// This is the LAST line, not the first: the governing reason belongs in a
/// [TerraBanner] on the page, where it is read before the button is reached.
/// This catches whoever pressed first and read second — which, on site, is
/// most people.
class BlockedAction extends StatelessWidget {
  const BlockedAction({
    super.key,
    required this.child,
    required this.reason,
    this.icon = Icons.lock_outline,
  });

  final Widget child;

  /// Why the control is dead, as one sentence in the user's language.
  ///
  /// `null` means NOT blocked — the child is returned untouched, so a caller
  /// can wrap unconditionally and let the reason decide.
  final String? reason;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final r = reason;
    if (r == null) return child;
    return GestureDetector(
      // `opaque`, so a tap that lands on the disabled child — which registers
      // no gesture recognisers of its own and therefore claims nothing —
      // still arrives here instead of falling through to the page.
      behavior: HitTestBehavior.opaque,
      onTap: () => showSnack(context, r, icon: icon),
      child: child,
    );
  }
}
