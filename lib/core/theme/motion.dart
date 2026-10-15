import 'package:flutter/material.dart';

import 'color_tokens.dart';
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

/// Whether the phone asks for less movement (Accessibility → Remove
/// animations, and the battery saver on some skins).
///
/// Honoured by everything added below. Motion that cannot be turned off is
/// not polish, it is an obstacle for whoever switched it off — and on site
/// that switch is often flipped to save battery, not for comfort.
bool reduceMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Lateral slide + fade when the bottom bar switches tab.
///
/// The branch bodies sit in an `IndexedStack`, which swaps with no motion at
/// all, so a tab tap feels like the screen was replaced by a cut. This gives
/// it the one movement that reads as "a SIBLING screen, at the same depth" —
/// sideways, in the direction of travel — as opposed to the forward rise that
/// [TerraPageTransitions] gives a pushed screen.
///
/// Only the ARRIVING screen is animated, and the subtree is never swapped:
/// wrapping the shell in an `AnimatedSwitcher` would keep a second copy of it
/// alive for the length of the transition and throw away each branch's
/// scroll position and form state — the very thing `StatefulShellRoute`
/// exists to preserve.
class TabSwap extends StatefulWidget {
  const TabSwap({super.key, required this.index, required this.child});

  /// Branch index. A change is what starts the movement.
  final int index;
  final Widget child;

  @override
  State<TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<TabSwap> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    duration: Dimens.motionMedium,
    vsync: this,
    value: 1,
  );

  /// +1 = moved to a tab on the right, so the new screen comes from the right.
  double _dir = 1;

  @override
  void didUpdateWidget(TabSwap old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _dir = widget.index > old.index ? 1 : -1;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final t = curve.value;
        return Opacity(
          // Never to zero: a screen that blanks out between tabs reads as a
          // reload, and the work is not being reloaded.
          opacity: 0.35 + 0.65 * t,
          child: Transform.translate(
            offset: Offset((1 - t) * 26 * _dir, 0),
            child: child,
          ),
        );
      },
    );
  }
}

/// Press feedback for anything tappable that is NOT a [ListCard].
///
/// The shrink is the same 0.975 the cards use, so one gesture does not feel
/// different depending on which widget happens to be under the finger. On a
/// touch screen this is the ONLY feedback there is: a hover colour is never
/// seen, because the finger covers the spot it touches.
///
/// The press is watched with a [Listener], NOT a `GestureDetector`. A pointer
/// listener never enters the gesture arena, so a child that already handles
/// its own taps — an `InkWell`, a button — keeps them. A `GestureDetector`
/// here would COMPETE for the same tap and one of the two would silently
/// lose, which on this app means a row that lights up and does nothing.
///
/// [onTap] is therefore optional: pass it only when the child does not
/// already handle the tap itself.
class TapScale extends StatefulWidget {
  const TapScale({super.key, required this.child, this.onTap, this.scale = 0.975});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final inti = Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Dimens.motionFast,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
    if (widget.onTap == null) return inti;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: inti);
  }
}

/// One grey block standing in for text or a figure that has not arrived.
///
/// Sized in the shape of what it replaces, so the layout does not jump when
/// the real content lands. A spinner says "wait"; this says "here is the
/// list, and these are its rows" — the screen is already legible before the
/// data is there.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 7});

  /// `null` = fill the available width.
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: w.line,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Sweeps a soft highlight across its child, left to right, forever.
///
/// Wraps a whole skeleton screen ONCE rather than each block, so the sweep
/// crosses the page as a single light instead of every row flickering on its
/// own clock.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    duration: const Duration(milliseconds: 1250),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // With animations off the blocks simply sit there — still a readable
    // layout, just without the sweep.
    if (reduceMotion(context)) return widget.child;
    final w = context.colors;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // The highlight is a narrow band; the rest of the gradient is
          // transparent so the blocks keep their own colour.
          colors: [
            Colors.transparent,
            w.surface.withValues(alpha: 0.75),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: _Sweep(_c.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// Slides a gradient from fully off the left edge to fully off the right.
class _Sweep extends GradientTransform {
  const _Sweep(this.t);

  /// 0 → 1 over one pass.
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * t - 1), 0, 0);
}

/// A list of card-shaped placeholders — the stand-in for any screen whose
/// content is a list of [ListCard]s.
///
/// [rows] is deliberately small: a screenful is enough to say "a list is
/// coming", and more would be inventing a length nobody knows yet.
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.rows = 4, this.leading = true});

  final int rows;

  /// Whether each row starts with a round avatar-sized block.
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(Dimens.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 11),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: w.surface,
                  borderRadius: BorderRadius.circular(Dimens.radiusCard),
                  boxShadow: w.shadow,
                ),
                child: Row(
                  children: [
                    if (leading) ...[
                      const SkeletonBox(width: 44, height: 44, radius: 22),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Varying widths: rows of identical bars read as a
                          // loading graphic, not as text about to arrive.
                          SkeletonBox(width: i.isEven ? 150 : 118, height: 15),
                          const SizedBox(height: 9),
                          SkeletonBox(width: i.isEven ? 96 : 134, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
