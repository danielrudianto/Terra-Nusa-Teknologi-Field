import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/util/app_version.dart';

void main() {
  test('reads like the server', () {
    expect(parseVersion('0.2.1'), [0, 2, 1]);
    expect(parseVersion('0.2.1+7'), [0, 2, 1]);
    expect(parseVersion('v0.2'), [0, 2]);
    expect(parseVersion('0.2.0'), [0, 2]);
    expect(parseVersion(null), [0]);
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
