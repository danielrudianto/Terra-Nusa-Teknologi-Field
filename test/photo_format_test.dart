import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/device/camera.dart';

/// Jenis foto yang dikirim ke server.
///
/// DIMINTA DANIEL, 14 Oktober 2026: foto dikompres ke WebP supaya lebih
/// kecil. Yang dijaga di sini satu hal yang tidak bersuara ketika salah:
/// antrean unggah memuat KEDUA jenis sekaligus tepat sesudah perubahan itu.
/// HP yang memperbarui aplikasinya sementara masih ada foto yang menunggu
/// tetap menyimpan berkas `.jpg` di antrean — dan foto itu harus naik
/// sebagai JPEG. Satu nilai tetap akan salah melabeli salah satu sisinya,
/// lalu kantor disajikan gambar yang peramban menolak menggambarnya.
void main() {
  List<int> jpeg() => [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(20, 0)];

  group('photoContentType', () {
    test('WebP dikenali dari RIFF....WEBP', () {
      final webp = <int>[
        0x52, 0x49, 0x46, 0x46, // RIFF
        0xD0, 0x07, 0x00, 0x00, // panjang
        0x57, 0x45, 0x42, 0x50, // WEBP
        0x56, 0x50, 0x38, 0x20, // VP8
      ];
      expect(photoContentType(webp), 'image/webp');
    });

    test('JPEG tetap JPEG', () {
      expect(photoContentType(jpeg()), 'image/jpeg');
    });

    test('panjangnya di tengah TIDAK diperiksa', () {
      // Empat bita panjang boleh berisi apa pun. Diperiksa sebagai satu
      // awalan tetap `RIFFWEBP`, setiap foto WebP yang sah akan ditolak.
      for (final n in [0, 1, 0xFF]) {
        final b = <int>[
          0x52, 0x49, 0x46, 0x46,
          n, n, n, n,
          0x57, 0x45, 0x42, 0x50,
        ];
        expect(photoContentType(b), 'image/webp', reason: 'panjang $n');
      }
    });

    test('RIFF yang BUKAN WebP tidak diaku WebP', () {
      // RIFF juga wadah WAV dan AVI.
      final wav = <int>[
        0x52, 0x49, 0x46, 0x46,
        0x00, 0x00, 0x00, 0x00,
        0x57, 0x41, 0x56, 0x45, // WAVE
      ];
      expect(photoContentType(wav), 'image/jpeg');
    });

    test('berkas yang lebih pendek dari 12 bita tidak melimpah', () {
      // `bytes[11]` pada berkas enam bita adalah RangeError, dan galat itu
      // terjadi di dalam pengunggah — antreannya macet, bukan satu foto
      // yang ditolak.
      for (final n in [0, 1, 4, 6, 11]) {
        expect(photoContentType(List.filled(n, 0x52)), 'image/jpeg',
            reason: '$n bita');
      }
    });
  });
}
