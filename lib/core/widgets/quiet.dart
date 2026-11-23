import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';

/// THE QUIET LOOK — the pieces of the Activity page redesign (22 Nov 2026),
/// shared so the Reports page reads the same (Daniel, 23 Nov 2026: "Ini di
/// Laporan harian busuk pisan. Redesign samain dong").
///
/// White panels with a soft shadow, big plain figures, the status as a
/// coloured WORD instead of a pill, and black for the main button.

/// White card with the app's soft two-layer shadow.
class QuietPanel extends StatelessWidget {
  const QuietPanel({super.key, required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: w.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: w.shadow,
      ),
      child: child,
    );
  }
}

/// One summary figure: dot + label, the big number with its unit, and a
/// faint line under it.
class QuietFigure extends StatelessWidget {
  const QuietFigure({
    super.key,
    required this.dot,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
  });

  final Color dot;
  final String label;
  final String value;
  final String unit;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          QuietLabel(dot: dot, text: label),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: w.ink, letterSpacing: -0.3),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: w.muted),
                ),
              ],
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: w.faint)),
        ],
      ),
    );
  }
}

/// Small dot + muted label — "● Pengeboran".
class QuietLabel extends StatelessWidget {
  const QuietLabel({super.key, required this.dot, required this.text});

  final Color dot;
  final String text;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: w.muted)),
        ),
      ],
    );
  }
}

/// Group heading: CODE bold, the name beside it muted, an optional action
/// at the end.
class QuietHeading extends StatelessWidget {
  const QuietHeading({super.key, required this.code, this.name = '', this.trailing});

  final String code;
  final String name;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: 2, bottom: trailing == null ? 10 : 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: code,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: w.ink),
                  ),
                  if (name.isNotEmpty)
                    TextSpan(
                      text: '   $name',
                      style: TextStyle(fontSize: 12.5, color: w.muted),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A period chip: black when chosen, white with a hairline when not. No
/// checkmark — the colour already says which one is on.
class QuietChip extends StatelessWidget {
  const QuietChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    final fg = selected ? w.surface : w.ink;
    return Material(
      color: selected ? w.ink : w.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? w.ink : w.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          // 44 high inside a 48 touch row: the Wrap's runSpacing makes up
          // the rest.
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The main action: black, like "Kirim ke WA".
ButtonStyle quietPrimary(BuildContext context) {
  final w = context.colors;
  return FilledButton.styleFrom(backgroundColor: w.ink, foregroundColor: w.surface);
}
