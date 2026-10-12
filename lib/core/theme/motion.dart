import 'package:flutter/material.dart';

import 'dimens.dart';

/// Motion for the whole app, in ONE place.
///
/// The vocabulary is the same one the office ERP uses (`--gerak-cepat` 140 ms,
/// `--gerak-sedang` 220 ms): fast for something the finger just did, medium
/// for something arriving. Nothing here is decoration — every movement says
/// "this is new" or "this changed", because a foreman chasing a truck reads
/// motion, not labels.
///
/// Everything is deliberately SHORT. Long, pretty transitions read as lag on
/// a cheap phone in the sun, and the work does not wait.

/// Page transition used for every pushed route.
///
/// A rise of a few percent plus a fade: enough to say "a new screen came in
/// from the work you just tapped", without the full-screen slide that makes
/// deep stacks feel heavy. Declared once in [ThemeData.pageTransitionsTheme]
/// instead of per route, so no screen can drift out of the vocabulary.
class TerraPageTransitions extends PageTransitionsBuilder {
  const TerraPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    // The screen being covered steps back a little instead of just sitting
    // there, so the two layers read as a stack.
    final leaving = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(enter),
        child: ScaleTransition(
          scale: Tween<double>(begin: 1, end: 0.985).animate(leaving),
          child: child,
        ),
      ),
    );
  }
}

/// One item arriving in a list: a short rise and fade, started on first build.
///
/// [order] staggers a group — item 0 starts now, item 1 a beat later — so a
/// list reads as filling in rather than appearing all at once. The stagger is
/// capped: past a handful of items the wait would be noticed, and a long list
/// must never make the user watch it assemble.
class AppearIn extends StatelessWidget {
  const AppearIn({super.key, required this.child, this.order = 0});

  final Widget child;
  final int order;

  static const _step = Duration(milliseconds: 45);
  static const _maxStagger = 5;

  @override
  Widget build(BuildContext context) {
    final delay = _step * (order > _maxStagger ? _maxStagger : order);
    return TweenAnimationBuilder<double>(
      // The key restarts the entrance when the item itself changes identity.
      tween: Tween<double>(begin: 0, end: 1),
      duration: Dimens.motionMedium + delay,
      curve: Interval(
        delay.inMilliseconds / (Dimens.motionMedium + delay).inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: child,
    );
  }
}

/// A number that CHANGES should be seen changing: the old value leaves
/// upward, the new one arrives from below, like a counter rolling over.
///
/// Used for the figures people watch during work — drilled depth, poured
/// volume — not for every label.
class AnimatedFigure extends StatelessWidget {
  const AnimatedFigure(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Dimens.motionMedium,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.35), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      // Same text = same child = no animation; only a real change moves.
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}
