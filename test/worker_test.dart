import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/workers/worker.dart';

void main() {
  final today = DateTime(2026, 10, 8, 15, 30);

  group('belongsTo', () {
    test('main project always counts', () {
      const k = Worker(uuid: 'a', name: 'Asep', projectId: 5);
      expect(k.belongsTo(5, today), isTrue);
      expect(k.belongsTo(6, today), isFalse);
    });

    test('last attendance counts for ${Worker.recentDays} days', () {
      final k = Worker(uuid: 'a', name: 'Asep', lastProjectId: 7, lastSeenDate: DateTime(2026, 9, 24));
      expect(k.belongsTo(7, today), isTrue, reason: 'exactly 14 days ago');
      final old = Worker(uuid: 'a', name: 'Asep', lastProjectId: 7, lastSeenDate: DateTime(2026, 9, 23));
      expect(old.belongsTo(7, today), isFalse, reason: '15 days ago');
    });

    test('borrowed worker counts at both sites', () {
      final k = Worker(uuid: 'a', name: 'Asep', projectId: 5, lastProjectId: 7, lastSeenDate: DateTime(2026, 10, 7));
      expect(k.projectsOn(today), {5, 7});
    });

    test('no project and no recent attendance counts nowhere', () {
      final k = Worker(uuid: 'a', name: 'Asep', lastProjectId: 7, lastSeenDate: DateTime(2026, 1, 1));
      expect(k.projectsOn(today), isEmpty);
    });
  });

  group('possibleDuplicates', () {
    const all = [
      Worker(uuid: '1', name: 'Asep Saepudin', phone: '0812-3456-789'),
      Worker(uuid: '2', name: 'Budi'),
      Worker(uuid: '3', name: 'Asepudin'),
    ];

    test('first name matches the full name, not a longer word', () {
      final d = possibleDuplicates(all, uuid: 'new', name: 'asep');
      expect(d.map((w) => w.uuid), ['1']);
    });

    test('same phone in another format', () {
      final d = possibleDuplicates(all, uuid: 'new', name: 'Ujang', phone: '+62 812 3456 789');
      expect(d.map((w) => w.uuid), ['1']);
    });

    test('the worker being edited is not its own duplicate', () {
      expect(possibleDuplicates(all, uuid: '2', name: 'Budi'), isEmpty);
    });

    test('short phone fragments are ignored', () {
      expect(possibleDuplicates(all, uuid: 'new', name: 'Ujang', phone: '0812'), isEmpty);
    });
  });
}
