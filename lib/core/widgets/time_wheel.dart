import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/dimens.dart';
import '../util/format.dart';

/// Pick a time of day: quick "minutes ago" buttons, then a 24-hour wheel.
///
/// Replaces the Material clock dial, which on site was hard to read (two
/// rings of 0–23 numbers) and needs two precise taps for hour and minute.
/// Here the common case — "just now" or "a few minutes ago" — is one tap,
/// and anything else is a thumb scroll. Returns null when dismissed.
///
/// The date stays the one of [initial]; a quick button may cross midnight,
/// since it counts back from now.
Future<DateTime?> showTimeWheel(
  BuildContext context, {
  required DateTime initial,
  String title = 'Jam berapa?',
  bool quickPicks = true,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    // Lets the sheet grow past half the screen; the content scrolls when the
    // phone is short (small screens overflowed by ~50 px).
    isScrollControlled: true,
    builder: (_) => _TimeWheel(initial: initial.toLocal(), title: title, quickPicks: quickPicks),
  );
}

class _TimeWheel extends StatefulWidget {
  const _TimeWheel({required this.initial, required this.title, required this.quickPicks});

  final DateTime initial;
  final String title;
  final bool quickPicks;

  @override
  State<_TimeWheel> createState() => _TimeWheelState();
}

class _TimeWheelState extends State<_TimeWheel> {
  late DateTime _value = widget.initial;

  /// Bumped to rebuild the wheel at a new position after a quick pick.
  int _wheelKey = 0;

  void _quick(Duration ago) {
    setState(() {
      final now = DateTime.now().subtract(ago);
      _value = DateTime(now.year, now.month, now.day, now.hour, now.minute);
      _wheelKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Dimens.pagePadding, 0, Dimens.pagePadding, Dimens.pagePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title and the chosen time on one line, to save height.
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: w.ink)),
                ),
                Text(
                  formatTime(_value),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: w.brand,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (widget.quickPicks) ...[
              const SizedBox(height: 10),
              // One row of four equal buttons — a wrapped second row cost height.
              Row(
                children: [
                  for (final (i, (label, ago)) in const [
                    ('Sekarang', Duration.zero),
                    ('−5 mnt', Duration(minutes: 5)),
                    ('−15 mnt', Duration(minutes: 15)),
                    ('−30 mnt', Duration(minutes: 30)),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, Dimens.minTouch),
                        ),
                        onPressed: () => _quick(ago),
                        child: FittedBox(child: Text(label)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: 150,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: w.ink),
                  ),
                ),
                child: CupertinoDatePicker(
                  key: ValueKey(_wheelKey),
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: _value,
                  onDateTimeChanged: (t) => setState(
                    () => _value = DateTime(_value.year, _value.month, _value.day, t.hour, t.minute),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: Dimens.minTouch + 4,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _value),
                child: Text('Pakai jam ${formatTime(_value)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
