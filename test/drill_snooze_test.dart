import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/device/drill_snooze.dart';
import 'package:terrabot_field/core/device/notifications.dart';

void main() {
  group('DrillSnooze.sampaiBesok', () {
    test('siang hari -> besok pukul 07.00', () {
      final s = DrillSnooze.sampaiBesok(DateTime(2026, 10, 19, 12, 30));
      expect(s, DateTime(2026, 10, 20, 7));
    });

    test('dini hari TETAP besok, bukan pagi ini', () {
      // Yang menekannya pukul tiga pagi bermaksud "sampai hari kerja
      // berikutnya", bukan "bangunkan saya empat jam lagi".
      final s = DrillSnooze.sampaiBesok(DateTime(2026, 10, 19, 3));
      expect(s, DateTime(2026, 10, 20, 7));
    });

    test('menyeberangi akhir bulan', () {
      final s = DrillSnooze.sampaiBesok(DateTime(2026, 10, 31, 22));
      expect(s, DateTime(2026, 11, 1, 7));
    });

    test('menyeberangi akhir tahun', () {
      final s = DrillSnooze.sampaiBesok(DateTime(2026, 12, 31, 22));
      expect(s, DateTime(2027, 1, 1, 7));
    });
  });

  group('DrillSnooze.menunda', () {
    final s = DrillSnooze(until: DateTime(2026, 10, 20, 7));

    test('sebelum jam bangun: masih diam', () {
      expect(s.menunda(DateTime(2026, 10, 20, 6, 59)), isTrue);
    });

    test('tepat jam bangun: sudah berbunyi lagi', () {
      expect(s.menunda(DateTime(2026, 10, 20, 7)), isFalse);
    });

    test('penundaan kemarin tidak membungkam hari ini', () {
      expect(s.menunda(DateTime(2026, 10, 21, 8)), isFalse);
    });
  });

  group('encode/decode', () {
    test('pulang pergi', () {
      final a = DrillSnooze(until: DateTime(2026, 10, 20, 7));
      final b = DrillSnooze.decode(a.encode());
      expect(b?.until, a.until);
    });

    test('isi rusak -> null, bukan lempar', () {
      expect(DrillSnooze.decode(null), isNull);
      expect(DrillSnooze.decode(''), isNull);
      expect(DrillSnooze.decode('bukan json'), isNull);
      expect(DrillSnooze.decode('{"until":"entah"}'), isNull);
    });
  });

  group('jadwal pengingat bor', () {
    test('mulai 45 menit, lalu tiap 15 menit, delapan kali', () {
      // Diperketat 19 Okt 2026: dulu 1 jam + tiap 30 menit x 5.
      expect(Notifications.drillIdleFirst, const Duration(minutes: 45));
      expect(Notifications.drillIdleEvery, const Duration(minutes: 15));
      expect(Notifications.drillIdleCount, 8);
    });

    test('bunyi terakhir masih di bawah tiga jam', () {
      // Lewat itu, rig yang memang sedang menunggu beton akan dibuat
      // berbunyi sepanjang hari — dan alarm sepanjang hari adalah alarm
      // yang dimatikan orang.
      final terakhir = Notifications.drillIdleFirst +
          Notifications.drillIdleEvery * (Notifications.drillIdleCount - 1);
      expect(terakhir.inMinutes, lessThan(180));
    });
  });
}
