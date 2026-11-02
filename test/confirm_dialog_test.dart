import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/i18n.dart';
import 'package:terrabot_field/core/widgets/confirm.dart';

/// `askConfirm` must answer YES only when someone said yes.
///
/// Its own documentation states the contract: "a dismissed dialog (back
/// button, tap outside) is a NO". Everything that undoes a finished record
/// leans on it — reopening a closed drill log, reopening a closed casting
/// log. If a dismissal ever came back as `true`, a sleeve brushing the screen
/// outside the dialog would reopen a log the office has already been told is
/// finished, and nothing on screen would say it happened.
///
/// The buttons are found by TYPE, not by their label, so the tests do not
/// break when the copy is retranslated — and so that swapping the two
/// buttons round during a restyle, which would make Cancel the confirming
/// one, fails here instead of on a rig.
void main() {
  const title = 'Buka lagi?';

  Future<_Answer> open(WidgetTester tester, {bool danger = false}) async {
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
                answer.value = await askConfirm(
                  context,
                  title: title,
                  body: 'Lognya dapat diubah lagi.',
                  confirmLabel: 'Buka',
                  danger: danger,
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
    expect(find.text(title), findsOneWidget, reason: 'the dialog should open');
    return answer;
  }

  testWidgets('confirming answers yes', (tester) async {
    final answer = await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(answer.returned, isTrue);
    expect(answer.value, isTrue);
    expect(find.text(title), findsNothing);
  });

  testWidgets('cancelling answers no', (tester) async {
    final answer = await open(tester);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(answer.returned, isTrue);
    expect(answer.value, isFalse);
    expect(find.text(title), findsNothing);
  });

  testWidgets('tapping outside answers no, never yes', (tester) async {
    final answer = await open(tester);

    // The barrier, well clear of the dialog box.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing, reason: 'it should close');
    expect(answer.returned, isTrue);
    expect(answer.value, isFalse, reason: 'a dismissal is a NO');
  });

  testWidgets('the system back button answers no', (tester) async {
    final answer = await open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(title), findsNothing);
    expect(answer.returned, isTrue);
    expect(answer.value, isFalse, reason: 'back is a NO');
  });

  testWidgets('danger paints the confirm button red without swapping it',
      (tester) async {
    final answer = await open(tester, danger: true);

    // Still the FilledButton that confirms. If a restyle ever reorders the
    // actions, the red button becomes Cancel and this fails.
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(answer.value, isTrue);
  });
}

/// Holds what `askConfirm` answered, and whether it answered at all.
class _Answer {
  bool? value;
  bool returned = false;
}
