import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/casting/concrete_suppliers.dart';

void main() {
  final all = <Map<String, Object?>>[
    {'id': 1, 'name': 'Adhimix', 'projectIDs': [10, 11]},
    {'id': 2, 'name': 'Merak Jaya', 'projectIDs': [11]},
    {'id': 3, 'name': 'Varia', 'projectIDs': <int>[]},
    {'id': 4, 'name': 'Lama'}, // pulled before projectIDs existed
  ];

  List<Object?> ids(List<Map<String, Object?>> l) => [for (final s in l) s['id']];

  test('only suppliers with a PO in the project', () {
    final r = suppliersForProject(all, 11);
    expect(r.narrowed, isTrue);
    expect(ids(r.suppliers), [1, 2]);
  });

  test('no PO in the project: everything', () {
    final r = suppliersForProject(all, 99);
    expect(r.narrowed, isFalse);
    expect(r.suppliers.length, 4);
  });

  test('the supplier already chosen stays on the list', () {
    final r = suppliersForProject(all, 10, keepId: 3);
    expect(r.narrowed, isTrue);
    expect(ids(r.suppliers), [1, 3]);
  });

  test('a kept supplier alone does not count as a PO', () {
    final r = suppliersForProject(all, 99, keepId: 3);
    expect(r.narrowed, isFalse);
    expect(r.suppliers.length, 4);
  });

  test('unknown project: everything', () {
    expect(suppliersForProject(all, null).suppliers.length, 4);
  });
}
