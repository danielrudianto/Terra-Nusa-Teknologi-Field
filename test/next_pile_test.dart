import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/gate/next_pile.dart';

Map<String, Object?> pile(
  String uuid,
  String code, {
  int project = 7,
  int sortOrder = 0,
  String status = 'sudah_bor',
  String? checkedAt,
  bool deleted = false,
}) =>
    {
      'uuid': uuid,
      'code': code,
      'projectID': project,
      'sortOrder': sortOrder,
      'status': status,
      'checkedAt': checkedAt,
      'isDelete': deleted,
    };

List<String> codes(List<Map<String, Object?>> piles) => [for (final p in piles) '${p['code']}'];

void main() {
  test('the pile point just recorded is not offered again', () {
    final all = [pile('a', 'PP.D13'), pile('b', 'PP.D14')];
    expect(codes(pilesForSameTruck(all, projectId: 7, currentUuid: 'a')), ['PP.D14']);
  });

  test('another project is left out', () {
    final all = [pile('a', 'PP.D13'), pile('b', 'PP.D14'), pile('c', 'X.1', project: 9)];
    expect(codes(pilesForSameTruck(all, projectId: 7, currentUuid: 'a')), ['PP.D14']);
  });

  test('a confirmed, already-cast or deleted pile point is left out', () {
    final all = [
      pile('a', 'PP.D13'),
      pile('b', 'PP.D14', checkedAt: '2026-11-18T08:00:00+07:00'),
      pile('c', 'PP.D15', status: 'sudah_cor'),
      pile('d', 'PP.D16', deleted: true),
      pile('e', 'PP.D17', status: 'belum_bor'),
    ];
    expect(codes(pilesForSameTruck(all, projectId: 7, currentUuid: 'a')), ['PP.D17']);
  });

  test('ordered by sortOrder, then by code', () {
    final all = [
      pile('a', 'PP.D13'),
      pile('b', 'PP.B2', sortOrder: 2),
      pile('c', 'PP.C9', sortOrder: 1),
      pile('d', 'PP.A1', sortOrder: 2),
    ];
    expect(
      codes(pilesForSameTruck(all, projectId: 7, currentUuid: 'x')),
      ['PP.D13', 'PP.C9', 'PP.A1', 'PP.B2'],
    );
  });

  test('the project id compares the same as text or number', () {
    final all = [pile('a', 'PP.D13'), pile('b', 'PP.D14')];
    expect(pilesForSameTruck(all, projectId: '7', currentUuid: 'a').length, 1);
  });

  test('nothing to offer gives an empty list', () {
    expect(pilesForSameTruck(const [], projectId: 7, currentUuid: 'a'), isEmpty);
    expect(pilesForSameTruck([pile('a', 'PP.D13')], projectId: 7, currentUuid: 'a'), isEmpty);
  });
}
