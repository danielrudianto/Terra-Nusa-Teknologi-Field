import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/sync/office_notice.dart';

/// An office notice (log deleted / corrected) is stored in meta as text and
/// read back by the log screen. Broken here = the screen goes silent again
/// when the log is deleted, exactly the complaint of 22 Nov 2026.
void main() {
  test('round trip keeps everything', () {
    final n = OfficeNotice(at: DateTime.parse('2026-11-22T09:40:00+07:00'), by: 'Ade', note: 'Alasan: salah titik');
    final back = OfficeNotice.decode(n.encode())!;
    expect(back.by, 'Ade');
    expect(back.note, 'Alasan: salah titik');
    expect(back.at, DateTime.parse('2026-11-22T09:40:00+07:00'));
  });

  test('empty or broken = no notice, not an error', () {
    expect(OfficeNotice.decode(null), isNull);
    expect(OfficeNotice.decode(''), isNull);
    expect(OfficeNotice.decode('{not json'), isNull);
  });

  test('a notice without time and name still reads', () {
    final back = OfficeNotice.decode(const OfficeNotice().encode())!;
    expect(back.at, isNull);
    expect(back.by, isNull);
  });

  test('delete and edit keys of one uuid do not collide', () {
    expect(officeDeletedKey('a'), isNot(officeEditedKey('a')));
  });
}
