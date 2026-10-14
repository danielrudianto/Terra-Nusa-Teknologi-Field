import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/app_version.dart';

void main() {
  test('reads like the server', () {
    expect(parseVersion('0.2.1'), [0, 2, 1, 0]);
    expect(parseVersion('v0.2'), [0, 2, 0, 0]);
    expect(parseVersion('0.2.0'), [0, 2, 0, 0]);
    expect(parseVersion(null), [0, 0, 0, 0]);
    expect(parseVersion('abc'), [0, 0, 0, 0]);
  });

  test('the build number counts', () {
    // Asked for by Daniel on 14 Oct 2026: a release that only raises the
    // build number must be forceable. Everything after '+' used to be
    // dropped, so 1.0.0+10 and 1.0.0+13 read the same.
    expect(parseVersion('0.2.1+7'), [0, 2, 1, 7]);
    expect(parseVersion('1.0.1+14'), [1, 0, 1, 14]);
    expect(compareVersions('1.0.0+10', '1.0.0+13'), lessThan(0));
    expect(compareVersions('1.0.0+14', '1.0.0+13'), greaterThan(0));
    expect(const AppOutdated(minVersion: '1.0.0+13').appliesTo('1.0.0+10'), isTrue);
    expect(const AppOutdated(minVersion: '1.0.0+13').appliesTo('1.0.0+13'), isFalse);
  });

  test('a threshold without a build number locks nobody out', () {
    // FOUR ZERO-FILLED NUMBERS, not a varying length. Trimmed as before,
    // '1.0.0' is [1] and '1.0.0+10' is [1, 0, 0, 10]; compared as lists the
    // shorter one always loses, so a FIELD_MIN_APP_VERSION=1.0.0 already in
    // .env would lock out the whole crew the moment the server deploys.
    expect(const AppOutdated(minVersion: '1.0.0').appliesTo('1.0.0+10'), isFalse);
    expect(const AppOutdated(minVersion: '1.0.0').appliesTo('1.0.0'), isFalse);
    expect(const AppOutdated(minVersion: '1.0.1').appliesTo('1.0.0+13'), isTrue,
        reason: 'a semantic version still wins');
  });

  test('compared as numbers, not text', () {
    expect(compareVersions('0.9.0', '0.10.0'), lessThan(0));
    expect(compareVersions('0.2', '0.2.0'), 0);
    expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
  });

  test('the block lifts as soon as the phone is new enough', () {
    const o = AppOutdated(minVersion: '0.2.0');
    expect(o.appliesTo('0.1.9'), isTrue);
    expect(o.appliesTo('0.2.0'), isFalse);
    expect(o.appliesTo('0.3.0'), isFalse);
  });

  test('kept in the phone and read back', () {
    const o = AppOutdated(minVersion: '0.2.0', downloadUrl: 'https://x/y.apk');
    final back = AppOutdated.decode(o.encode())!;
    expect(back.minVersion, '0.2.0');
    expect(back.downloadUrl, 'https://x/y.apk');
    expect(AppOutdated.decode('rusak'), isNull);
    expect(AppOutdated.fromContext({'minVersion': '0.2.0', 'downloadUrl': ''}).downloadUrl, isNull);
  });
}
