import 'package:flutter/material.dart';

import '../../core/theme/color_tokens.dart';

/// Which part of the tremie string a segment is.
enum TremiePart { pipe, bottom }

/// One tremie segment as an action row: a round badge (its number, or the
/// triangle for the tremie bottom), its length with where it hangs in the
/// hole, and the "Cabut" button.
///
/// The badges are joined by a thin vertical line so the list still reads as
/// one tremie string from top to bottom, without repeating the to-scale
/// cross-section above it.
class TremieSegmentTile extends StatelessWidget {
  const TremieSegmentTile({
    super.key,
    required this.part,
    this.number = 0,
    required this.title,
    this.subtitle,
    this.removed = false,
    this.lowest = false,
    this.first = false,
    this.last = false,
    this.trailing,
    this.onTap,
  });

  final TremiePart part;

  /// Segment position, shown in the badge (the tremie bottom shows a triangle).
  final int number;
  final String title;
  final String? subtitle;

  /// Pulled out of the hole.
  final bool removed;

  /// The lowest segment still in the hole (highlighted).
  final bool lowest;

  /// Top / bottom row: no joining line above / below the badge.
  final bool first;
  final bool last;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const _badge = 36.0;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final (bg, fg) = removed
        ? (w.line, w.muted)
        : lowest
            ? (w.okBg, w.okFg)
            : (w.brandSoft, w.brand);
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _badge,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The string joining the badges.
                  Column(
                    children: [
                      Expanded(child: Container(width: 2, color: first ? Colors.transparent : w.border)),
                      Expanded(child: Container(width: 2, color: last ? Colors.transparent : w.border)),
                    ],
                  ),
                  Container(
                    width: _badge,
                    height: _badge,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: part == TremiePart.bottom
                        ? Icon(Icons.change_history, size: 20, color: fg)
                        : Text('$number', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: fg)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: removed ? w.muted : w.ink,
                        decoration: removed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: lowest && !removed ? w.okFg : w.muted)),
                  ],
                ),
              ),
            ),
            if (trailing != null) Center(child: trailing),
          ],
        ),
      ),
    );
  }
}
