import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/theme/appearance.dart';

void main() {
  test('defaults', () {
    const a = Appearance();
    expect(a.mode, ThemeMode.system);
    expect(a.accent.id, 'biru');
    expect(a.textScale, 1.0);
  });

  test('roundtrip', () {
    const a = Appearance(mode: ThemeMode.dark, accentId: 'teal', textScale: 1.3);
    expect(Appearance.decode(a.encode()), a);
  });

  test('broken or unknown values fall back, never throw', () {
    expect(Appearance.decode(null), const Appearance());
    expect(Appearance.decode(''), const Appearance());
    expect(Appearance.decode('not json'), const Appearance());
    expect(Appearance.decode('[1,2]'), const Appearance());
    expect(Appearance.decode('{"mode":"disco","accent":"emas","scale":9}'), const Appearance());
  });

  test('unknown accent falls back to the default', () {
    expect(accentById('emas').id, 'biru');
    expect(accentById(null).id, 'biru');
  });
}
