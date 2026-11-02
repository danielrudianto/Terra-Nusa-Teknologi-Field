import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/widgets/swipe_confirm.dart';

/// What the swipe on "finish drilling" / "finish casting" must actually do.
///
/// The control exists so that a stray tap cannot close a log. That only holds
/// if three things are true, and none of them is visible from reading the
/// widget:
///
///   * a drag that stops short does NOTHING;
///   * a drag that lands fires exactly ONCE, even if dragged again while the
///     save is still in flight;
///   * a save that does not happen UNLOCKS it again.
///
/// The last one is the one that would hurt. `_submit` in the drill dialog
/// refuses and keeps the dialog open when ground level or the actual
/// coordinates are missing. If the thumb stayed locked at the end there, the
/// only way out of that dialog would be abandoning the whole entry — at the
/// hole, with a log already running.
void main() {
  // Wide enough that the thumb (56) leaves a real track behind it. The drags
  // below are deliberately far from the 70% threshold, so this stays true if
  // the thumb ever changes size.
  const width = 300.0;
  const short = Offset(40, 0);
  const full = Offset(width, 0);

  /// The thumb is the only `GestureDetector` inside the control; finding it
  /// by icon would break the moment it turns into a check mark.
  final thumb = find.descendant(
    of: find.byType(SwipeToConfirm),
    matching: find.byType(GestureDetector),
  );

  Future<void> show(
    WidgetTester tester, {
    required Future<bool> Function() onConfirm,
    bool enabled = true,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: SwipeToConfirm(
                  label: 'Geser',
                  doneLabel: 'Tersimpan',
                  onConfirm: onConfirm,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a drag that stops short does nothing', (tester) async {
    var calls = 0;
    await show(tester, onConfirm: () async {
      calls++;
      return true;
    });

    await tester.drag(thumb, short);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('Geser'), findsOneWidget);
    expect(find.text('Tersimpan'), findsNothing);
  });

  testWidgets('a drag that lands confirms once', (tester) async {
    var calls = 0;
    await show(tester, onConfirm: () async {
      calls++;
      return true;
    });

    await tester.drag(thumb, full);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Tersimpan'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('once confirmed it cannot be dragged again', (tester) async {
    var calls = 0;
    await show(tester, onConfirm: () async {
      calls++;
      return true;
    });

    await tester.drag(thumb, full);
    await tester.pumpAndSettle();
    await tester.drag(thumb, full);
    await tester.pumpAndSettle();

    expect(calls, 1);
  });

  testWidgets('a refused save unlocks it so it can be dragged again',
      (tester) async {
    var calls = 0;
    // First attempt refuses — the required field is still empty. Second one
    // goes through, as it would after the field is filled in.
    await show(tester, onConfirm: () async {
      calls++;
      return calls > 1;
    });

    await tester.drag(thumb, full);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Tersimpan'), findsNothing,
        reason: 'a refused save must not read as done');

    await tester.drag(thumb, full);
    await tester.pumpAndSettle();

    expect(calls, 2, reason: 'the thumb must be draggable again after a refusal');
    expect(find.text('Tersimpan'), findsOneWidget);
  });

  testWidgets('it stays dead while the save is still in flight',
      (tester) async {
    final gate = Completer<bool>();
    var calls = 0;
    await show(tester, onConfirm: () async {
      calls++;
      return gate.future;
    });

    await tester.drag(thumb, full);
    // `pump`, NOT `pumpAndSettle`: the spinner animates forever while the
    // save is pending, and settling would wait for an animation that never
    // ends.
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.drag(thumb, full);
    await tester.pump();
    expect(calls, 1, reason: 'a second drag must not start a second save');

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Tersimpan'), findsOneWidget);
  });

  testWidgets('disabled it does not move', (tester) async {
    var calls = 0;
    await show(
      tester,
      enabled: false,
      onConfirm: () async {
        calls++;
        return true;
      },
    );

    await tester.drag(thumb, full);
    await tester.pumpAndSettle();

    expect(calls, 0);
  });
}
