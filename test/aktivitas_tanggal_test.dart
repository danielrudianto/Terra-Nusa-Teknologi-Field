import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/home/aktivitas_hari_ini.dart';

/// Halaman Aktivitas memakai `susunKegiatan` yang sama dengan kartu
/// beranda, hanya dengan TANGGAL ACUAN yang berbeda. Yang diuji di sini
/// adalah bahwa acuannya benar-benar menentukan — kalau tidak, membuka
/// "kemarin" akan menampilkan daftar hari ini dan tidak ada yang
/// menyadarinya sampai angkanya dibawa ke rapat.
void main() {
  Map<String, Object?> bor(String kode, DateTime jam, {String status = 'selesai'}) => {
        'pilePointCode': kode,
        'pilePointID': 1,
        'endAt': jam.toIso8601String(),
        'status': status,
        'depthM': '12.50',
        'operatorName': 'Anura',
      };

  Map<String, Object?> cor(String kode, DateTime jam) => {
        'pilePointCode': kode,
        'pilePointID': 2,
        'endAt': jam.toIso8601String(),
        'status': 'selesai',
        'trucks': 4,
        'volumeM3': '22.50',
        'byName': 'Alif',
      };

  final kemarin = DateTime(2026, 10, 19, 14, 30);
  final hariIni = DateTime(2026, 10, 20, 9, 15);

  test('acuan kemarin hanya memuat kegiatan kemarin', () {
    final hasil = susunKegiatan({
      'drilling': [bor('SP.B48', kemarin), bor('SP.B49', hariIni)],
      'casting': [cor('PP.B63', kemarin)],
    }, kemarin);

    expect(hasil.map((k) => k.kode), ['SP.B48', 'PP.B63']);
  });

  test('acuan hari ini tidak memuat kemarin', () {
    final hasil = susunKegiatan({
      'drilling': [bor('SP.B48', kemarin), bor('SP.B49', hariIni)],
    }, hariIni);

    expect(hasil.map((k) => k.kode), ['SP.B49']);
  });

  test('terbaru di atas', () {
    final pagi = DateTime(2026, 10, 19, 8, 0);
    final sore = DateTime(2026, 10, 19, 16, 0);
    final hasil = susunKegiatan({
      'drilling': [bor('PAGI', pagi), bor('SORE', sore)],
    }, kemarin);

    expect(hasil.first.kode, 'SORE');
  });

  test('kegiatan tanpa jam dilewati, bukan ditaruh di pucuk', () {
    final hasil = susunKegiatan({
      'drilling': [
        {'pilePointCode': 'TANPA JAM', 'status': 'selesai', 'depthM': '5'},
        bor('SP.B48', kemarin),
      ],
    }, kemarin);

    expect(hasil.map((k) => k.kode), ['SP.B48']);
  });

  test('hari kosong menghasilkan daftar kosong, bukan galat', () {
    expect(susunKegiatan(const {}, kemarin), isEmpty);
    expect(
      susunKegiatan({'drilling': [bor('SP.B48', hariIni)]}, kemarin),
      isEmpty,
    );
  });

  test('log yang masih berjalan ditandai belum selesai', () {
    final hasil = susunKegiatan({
      'drilling': [bor('SP.B48', kemarin, status: 'berjalan')],
    }, kemarin);

    expect(hasil.single.selesai, isFalse);
  });
}
