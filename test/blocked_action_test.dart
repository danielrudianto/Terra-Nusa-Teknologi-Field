import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/widgets/blocked_action.dart';

/// `BlockedAction` wraps a control that is deliberately dead, so that
/// pressing it still answers "why".
///
/// Two things have to hold at once, and they pull against each other. When
/// there is no reason, the wrapper must be INVISIBLE — the child is returned
/// untouched, so a caller can wrap unconditionally and let the reason decide;
/// if the wrapper stayed in place it would swallow the taps of a control that
/// is perfectly alive. When there IS a reason, the tap must be caught even
/// though it lands on a disabled child that registers no gestures of its own
/// and therefore claims nothing — that is what `HitTestBehavior.opaque` is
/// for, and it is the whole reason this widget exists.
///
/// Lose the first and live buttons stop working. Lose the second and the
/// person standing next to a running rig presses a grey rectangle, gets
/// nothing, and phones the office.
void main() {
  const reason = 'Susun tremie dulu.';

  Future<void> pump(
    WidgetTester tester, {
    required String? why,
    VoidCallback? onTap,
    required Widget child,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BlockedAction(reason: why, onTap: onTap, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('no reason means the child is returned untouched', (tester) async {
    await pump(tester, why: null, child: const Text('tombol'));

    expect(
      find.descendant(
        of: find.byType(BlockedAction),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
      reason: 'an unblocked control must not be wrapped at all',
    );
  });

  testWidgets('no reason leaves a live button working', (tester) async {
    var taps = 0;
    await pump(
      tester,
      why: null,
      child: FilledButton(onPressed: () => taps++, child: const Text('tombol')),
    );

    await tester.tap(find.text('tombol'));
    await tester.pump();

    expect(taps, 1, reason: 'the wrapper must not swallow a live tap');
  });

  testWidgets('a reason catches the tap on a DISABLED child and says why',
      (tester) async {
    await pump(
      tester,
      why: reason,
      // Disabled, exactly as it is on the real screens: it registers no
      // gesture of its own, so without the opaque wrapper the tap would fall
      // straight through to the page and nothing would happen.
      child: const FilledButton(onPressed: null, child: Text('tombol')),
    );

    await tester.tap(find.text('tombol'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
  });

  testWidgets('onTap replaces the snack rather than adding to it',
      (tester) async {
    // Used when what is missing lives on ANOTHER screen: the tap is carried
    // straight to where the data is entered instead of being given
    // directions, which on site get skipped.
    var taps = 0;
    await pump(
      tester,
      why: reason,
      onTap: () => taps++,
      child: const FilledButton(onPressed: null, child: Text('tombol')),
    );

    await tester.tap(find.text('tombol'));
    await tester.pump();

    expect(taps, 1);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'one answer, not two');
  });
}
