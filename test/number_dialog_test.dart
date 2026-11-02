import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/i18n.dart';
import 'package:terrabot_field/core/widgets/number_dialog.dart';

/// `showNumberDialog` has THREE outcomes, and two of them look alike.
///
/// `null` means cancelled. `(null,)` means deliberately left empty, and is
/// only ever possible with [allowEmpty]. `(value,)` means a number. The
/// record-shaped middle case exists precisely so that "the user cancelled"
/// and "the user told us there is nothing to measure" cannot be confused —
/// a ground level that is genuinely absent must be storable as absent,
/// while a cancelled dialog must change nothing at all.
///
/// Collapse those two and a cancelled dialog silently writes an empty
/// measurement into a log that someone later signs. Nothing on screen would
/// show it. These tests pin all three apart.
///
/// The buttons are found by TYPE — TextButton cancels, FilledButton saves —
/// so retranslating the copy does not break the tests, and reordering the
/// two actions during a restyle does.
void main() {
  const title = 'Sounding';

  Future<_Result> open(
    WidgetTester tester, {
    double maxValue = 10,
    bool allowEmpty = false,
    double? initial,
    String? Function(double value)? validate,
  }) async {
    final result = _Result();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('id'),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result.value = await showNumberDialog(
                  context,
                  title: title,
                  label: 'Kedalaman',
                  icon: Icons.straighten,
                  suffix: 'm',
                  maxValue: maxValue,
                  initial: initial,
                  allowEmpty: allowEmpty,
                  validate: validate,
                );
                result.returned = true;
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
    return result;
  }

  testWidgets('cancelling returns null, not an empty value', (tester) async {
    final result = await open(tester, allowEmpty: true);
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    expect(result.value, isNull, reason: 'cancelled is null, never (null,)');
  });

  testWidgets('a typed number comes back', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), '3,5');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.$1, 3.5);
  });

  testWidgets('a dot is read as a decimal mark too', (tester) async {
    // The Android number keyboard puts comma and dot side by side, and
    // whoever is holding the phone must not have to know which one is
    // "correct".
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), '3.5');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.$1, 3.5);
  });

  testWidgets('a number past the maximum keeps the dialog open', (tester) async {
    final result = await open(tester, maxValue: 10);
    await tester.enterText(find.byType(TextField), '99');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget, reason: 'it must stay open');
    expect(result.returned, isFalse, reason: 'nothing may be returned');
    expect(find.byIcon(Icons.error_outline), findsOneWidget,
        reason: 'and it must say why');
  });

  testWidgets('zero is refused', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(result.returned, isFalse);
  });

  testWidgets('empty is refused when allowEmpty is off', (tester) async {
    final result = await open(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(result.returned, isFalse);
  });

  testWidgets('empty returns (null,) when allowEmpty is on', (tester) async {
    final result = await open(tester, allowEmpty: true);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result.returned, isTrue);
    expect(result.value, isNotNull,
        reason: 'deliberately empty is (null,), NOT a cancel');
    expect(result.value!.$1, isNull);
  });

  testWidgets('a failing validate keeps the dialog open and shows its sentence',
      (tester) async {
    final result = await open(
      tester,
      validate: (v) => v > 5 ? 'Lebih dalam dari rencana.' : null,
    );
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text(title), findsOneWidget);
    expect(result.returned, isFalse);
    expect(find.text('Lebih dalam dari rencana.'), findsOneWidget);
  });

  testWidgets('a passing validate lets the number through', (tester) async {
    final result = await open(
      tester,
      validate: (v) => v > 5 ? 'Lebih dalam dari rencana.' : null,
    );
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(result.value, isNotNull);
    expect(result.value!.$1, 3.0);
  });

  testWidgets('an initial value is shown with a comma, ready to edit',
      (tester) async {
    await open(tester, initial: 2.5);
    expect(find.text('2,50'), findsOneWidget);
  });
}

/// Holds what `showNumberDialog` returned, and whether it returned at all.
class _Result {
  (double?,)? value;
  bool returned = false;
}
