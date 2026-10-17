import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/device/update_available.dart';

/// AJAKAN memperbarui — bukan pemblokiran.
///
/// Diminta Daniel, 17 Okt 2026: "begitu ada update, arahkan dia untuk
/// update". Dibedakan tajam dari layar "Perbarui app", yang menggantikan
/// seluruh aplikasi ketika server MENOLAK versi ini: ambang penolakan baru
/// aman dinaikkan sesudah HP kru punya APK-nya, sedangkan ajakan ini aman
/// dinyalakan pada detik rilisnya terbit.
void main() {
  Map<String, Object?> pull({String? versi, Object? tautan = 'https://play/x'}) => {
        'locked': false,
        if (versi != null)
          'update': {'latestVersion': versi, 'downloadUrl': tautan},
      };

  group('membaca blok device.update', () {
    test('ada pembaruan', () {
      final u = UpdateAvailable.fromPull(pull(versi: '1.0.6+21'));
      expect(u!.latestVersion, '1.0.6+21');
      expect(u.downloadUrl, 'https://play/x');
    });

    test('tanpa kunci update = sudah terbaru', () {
      // Server menghilangkan kuncinya bila tidak ada yang lebih baru, dan
      // server LAMA tidak mengenalnya sama sekali. Keduanya harus `null`,
      // bukan galat.
      expect(UpdateAvailable.fromPull(pull()), isNull);
      expect(UpdateAvailable.fromPull({'locked': true}), isNull);
    });

    test('bukan peta sama sekali tidak melempar', () {
      expect(UpdateAvailable.fromPull(null), isNull);
      expect(UpdateAvailable.fromPull('bukan peta'), isNull);
      expect(UpdateAvailable.fromPull({'update': 'bukan peta'}), isNull);
    });

    test('versi kosong diabaikan', () {
      expect(UpdateAvailable.fromPull(pull(versi: '')), isNull);
    });

    test('tautan kosong menjadi null, bukan untai kosong', () {
      // Layar memutuskan menampilkan tombol dari ADA atau TIDAKNYA tautan;
      // untai kosong akan lolos dan menghasilkan tombol yang tidak membuka
      // apa pun.
      expect(UpdateAvailable.fromPull(pull(versi: '1.0.6+21', tautan: ''))!.downloadUrl, isNull);
      expect(UpdateAvailable.fromPull(pull(versi: '1.0.6+21', tautan: null))!.downloadUrl, isNull);
    });
  });

  group('simpan dan baca kembali', () {
    test('bolak-balik utuh', () {
      const a = UpdateAvailable(latestVersion: '1.0.6+21', downloadUrl: 'https://play/x');
      final b = UpdateAvailable.decode(a.encode())!;
      expect(b.latestVersion, a.latestVersion);
      expect(b.downloadUrl, a.downloadUrl);
    });

    test('tanpa tautan tetap utuh', () {
      const a = UpdateAvailable(latestVersion: '1.0.6+21');
      expect(UpdateAvailable.decode(a.encode())!.downloadUrl, isNull);
    });

    test('isi rusak tidak melempar', () {
      expect(UpdateAvailable.decode(null), isNull);
      expect(UpdateAvailable.decode(''), isNull);
      expect(UpdateAvailable.decode('{bukan json'), isNull);
      expect(UpdateAvailable.decode('{}'), isNull);
    });
  });

  group('penundaan', () {
    final kini = DateTime(2026, 10, 17, 9, 0);

    test('menunda versi yang sama sampai batasnya', () {
      final s = UpdateSnooze(version: '1.0.6+21', until: kini.add(const Duration(hours: 8)));
      expect(s.menunda('1.0.6+21', kini), isTrue);
      expect(s.menunda('1.0.6+21', kini.add(const Duration(hours: 7, minutes: 59))), isTrue);
      expect(s.menunda('1.0.6+21', kini.add(const Duration(hours: 8, minutes: 1))), isFalse);
    });

    test('TIDAK menunda versi yang LAIN', () {
      // Inti kenapa versinya ikut disimpan: menunda 1.0.6 tidak boleh
      // menyembunyikan 1.0.7 yang terbit besoknya — dan rilis yang justru
      // penting akan lewat tanpa seorang pun melihatnya.
      final s = UpdateSnooze(version: '1.0.6+21', until: kini.add(const Duration(hours: 8)));
      expect(s.menunda('1.0.7+22', kini), isFalse);
    });

    test('lamanya satu giliran kerja', () {
      expect(UpdateSnooze.durasi, const Duration(hours: 8));
    });

    test('bolak-balik utuh, dan isi rusak tidak melempar', () {
      final s = UpdateSnooze(version: '1.0.6+21', until: kini);
      final b = UpdateSnooze.decode(s.encode())!;
      expect(b.version, '1.0.6+21');
      expect(b.until, kini);
      expect(UpdateSnooze.decode('{bukan json'), isNull);
      expect(UpdateSnooze.decode('{"version":"","until":"2026-10-17T09:00:00"}'), isNull);
      expect(UpdateSnooze.decode('{"version":"1.0.6+21","until":"bukan tanggal"}'), isNull);
    });
  });
}
