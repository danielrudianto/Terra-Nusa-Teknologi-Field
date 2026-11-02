import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/i18n.dart';
import 'package:terrabot_field/core/widgets/confirm_code.dart';

/// Retyping the point code is the one check standing between a casting log
/// and the WRONG pile.
///
/// The mistake it catches is not misreading — it is tapping the wrong row in
/// the list. Whoever taps the wrong row is just as certain as whoever taps
/// the right one, so "are you sure?" gets answered "yes", the log lands on
/// another point, and it surfaces days later when those numbers have already
/// been used to compute volume. Retyping is a second channel that does not
/// share the error, because what gets typed comes from the pile in front of
/// the person rather than from the list they mis-tapped.
///
/// Everything here protects one of two properties:
///
///  * the answer must not be visible before it is given — a dialog that
///    shows the code only tests the ability to copy;
///  * what IS typed must be judged generously, because the person is wearing
///    gloves next to a running rig, and case, dots and hyphens were never the
///    point.
void main() {
  group('sharedCodePrefix', () {
    // Rule 1: only as far as every other code agrees.
    test('shows the part that is shared by the whole project', () {
      expect(sharedCodePrefix('PP.B52', ['PP.B1', 'PP.B60', 'PP.B52']), 'PP.B');
    });

    test('shows nothing when no two codes begin alike', () {
      expect(sharedCodePrefix('PP.B52', ['XX.A1']), '');
    });

    test('a code on its own still has its digits withheld', () {
      expect(sharedCodePrefix('PP.B52', const <String>[]), 'PP.B');
    });

    // Rule 2: stop before the first digit, however much is shared.
    test('stops before the first digit even when more is shared', () {
      // PP.B52 and PP.B54 share "PP.B5" — which would leave ONE keystroke,
      // one of ten possibilities, and the check would stop checking.
      expect(sharedCodePrefix('PP.B52', ['PP.B54']), 'PP.B');
    });

    test('a code that begins with a digit shows nothing', () {
      expect(sharedCodePrefix('12AB', const <String>[]), '');
    });

    // Rule 3: at least two characters left to type, whatever the rules above
    // worked out.
    test('always leaves at least two characters, with no digits to stop at',
        () {
      expect(sharedCodePrefix('ABCD', ['ABCE']), 'AB');
    });

    test('a code too short to shorten shows nothing', () {
      expect(sharedCodePrefix('B5', ['B6']), '');
      expect(sharedCodePrefix('A1', const <String>[]), '');
    });
  });

  group('askCodeConfirm', () {
    const code = 'PP.B52';
    const others = ['PP.B1', 'PP.B60'];

    /// Type into the field AND render a frame.
    ///
    /// The frame is not optional here. This dialog's confirm button is
    /// wrapped in a ValueListenableBuilder, so `onPressed` stays null until
    /// the controller's change has been rebuilt — and a tap on a button
    /// whose onPressed is null does nothing at all, silently. Without this
    /// pump the test taps a dead button and reads back "no answer", which
    /// looks exactly like the dialog refusing the code.
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
    }

    /// The mismatch SENTENCE naming both codes.
    ///
    /// Deliberately not `find.textContaining`: that also matches the
    /// EditableText the person just typed into, so looking for the typed code
    /// would find the input field and pass whether or not the sentence was
    /// ever shown.
    Finder sentenceNaming(String selected, String typed) =>
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '').contains(selected) &&
              (w.data ?? '').contains(typed),
        );

    Future<_Answer> open(WidgetTester tester) async {
      final answer = _Answer();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('id'),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  answer.value = await askCodeConfirm(
                    context,
                    code: code,
                    allCodes: others,
                  );
                  answer.returned = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget,
          reason: 'the dialog should open');
      return answer;
    }

    testWidgets('the chosen code is NOT shown before an answer is given',
        (tester) async {
      await open(tester);

      // "PP.B" is on screen as the field's prefix — that part distinguishes
      // nothing. The digits, which are the answer, must be nowhere.
      expect(find.textContaining(code), findsNothing);
    });

    testWidgets('confirm is dead until something is typed', (tester) async {
      await open(tester);

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull, reason: 'an empty field may not be confirmable');

      await type(tester, '5');

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNotNull);
    });

    testWidgets('typing just the remaining digits is accepted', (tester) async {
      final answer = await open(tester);
      await type(tester, '52');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(answer.value, isTrue);
    });

    testWidgets('typing the whole code is accepted too', (tester) async {
      // Someone who never noticed there was a prefix already on screen.
      final answer = await open(tester);
      await type(tester, 'PP.B52');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(answer.value, isTrue);
    });

    testWidgets('case, dots and hyphens are never a reason to refuse',
        (tester) async {
      // Typed on a phone keyboard, gloves on, beside a running rig.
      final answer = await open(tester);
      await type(tester, 'ppb52');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(answer.value, isTrue);
    });

    testWidgets('a wrong code is refused, and only THEN is the chosen one shown',
        (tester) async {
      final answer = await open(tester);
      await type(tester, '54');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(answer.returned, isFalse, reason: 'it must not confirm');
      expect(find.byType(TextField), findsOneWidget, reason: 'and stay open');

      // By now the code is no longer an answer that could be copied; it is
      // the only sentence explaining what just happened.
      expect(sentenceNaming(code, 'PP.B54'), findsOneWidget);
    });

    testWidgets('a wrong FULL code is echoed back as itself, not doubled',
        (tester) async {
      // The prefix is already on screen, so naively prepending it to what was
      // typed yields "PP.BPP.B54" — and the one sentence whose job is to
      // explain the mistake prints nonsense instead.
      final answer = await open(tester);
      await type(tester, 'PP.B54');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(answer.returned, isFalse);
      expect(sentenceNaming(code, 'PP.B54'), findsOneWidget,
          reason: 'echoed back as itself');
      expect(find.textContaining('PP.BPP.B'), findsNothing,
          reason: 'and not with the prefix stuck on twice');
    });

    testWidgets('tapping outside does NOT dismiss this one', (tester) async {
      // Deliberately unlike askConfirm: this dialog is the check itself, so
      // it may not be got rid of by a tap that lands anywhere.
      final answer = await open(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget, reason: 'still open');
      expect(answer.returned, isFalse);
    });

    testWidgets('cancelling answers no', (tester) async {
      final answer = await open(tester);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(answer.returned, isTrue);
      expect(answer.value, isFalse);
    });
  });
}

/// Holds what `askCodeConfirm` answered, and whether it answered at all.
class _Answer {
  bool? value;
  bool returned = false;
}
