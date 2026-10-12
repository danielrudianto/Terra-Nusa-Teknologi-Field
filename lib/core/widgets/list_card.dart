import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';

/// Tappable list card — `kartu-daftar` in `_mobile.scss`.
///
/// Shadow, NOT a border; radius 16; SHRINKS slightly when pressed. On a
/// touch screen the hover color is never seen — the finger covers the spot
/// it touches, and only motion is felt.
class ListCard extends StatefulWidget {
  const ListCard({super.key, required this.child, this.onTap, this.onLongPress, this.edgeColor});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Colored left border for status (e.g. red = rejected).
  final Color? edgeColor;

  @override
  State<ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<ListCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed && widget.onTap != null ? 0.975 : 1,
        duration: Dimens.motionFast,
        curve: Curves.easeOutCubic,
        child: Container(
          constraints: const BoxConstraints(minHeight: Dimens.minTouch),
          margin: const EdgeInsets.only(bottom: 11),
          decoration: BoxDecoration(
            color: w.surface,
            borderRadius: BorderRadius.circular(Dimens.radiusCard),
            boxShadow: w.shadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // The edge marks work in progress; when a point changes stage
              // the colour slides rather than jumping.
              AnimatedContainer(
                duration: Dimens.motionMedium,
                curve: Curves.easeOutCubic,
                width: widget.edgeColor == null ? 0 : 4,
                height: 64,
                color: widget.edgeColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
