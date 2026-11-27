import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/gs_check.dart';

void main() {
  group('GS check (27 Nov 2026)', () {
    test('SP.D3: 6819 for 681,9 is impossible, and the comma is guessed', () {
      expect(gsImpossible(6819.0, 681.741), isTrue);
      expect(gsSuggestion(6819.0, 681.741), closeTo(681.9, 1e-9));
      expect(gsSuggestion(6812.076, 681.996), closeTo(681.208, 1e-9));
    });

    test('within 30 cm needs nothing; 0,3 to 10 m asks first', () {
      expect(gsImpossible(681.9, 681.741), isFalse);
      expect(gsNeedsConfirm(681.9, 681.741), isFalse);
      expect(gsNeedsConfirm(683.0, 681.741), isTrue);
      expect(gsImpossible(691.7, 681.741), isFalse);
      expect(gsImpossible(692.0, 681.741), isTrue);
    });

    test('reference is the design GS, else the cut-off level', () {
      expect(gsReference(design: 681.7, cutOffLevel: 680.0), 681.7);
      expect(gsReference(design: null, cutOffLevel: 680.0), 680.0);
      expect(gsReference(), isNull);
      // A stored typo as "design" falls back to the cut-off level.
      expect(gsReference(design: 6819.0, cutOffLevel: 680.5), 680.5);
      expect(gsImpossible(6819.0, null), isFalse);
    });

    test('no guess when no shifted comma lands near the reference', () {
      expect(gsSuggestion(250.0, 681.7), isNull);
    });
  });
}
