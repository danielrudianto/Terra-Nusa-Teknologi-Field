import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/features/home/aktivitas_hari_ini.dart';

Map<String, Object?> bor({
  required String kode,
  String? endAt,
  String? startAt,
  String status = 'selesai',
  Object? depthM = 28.9,
}) =>
    {
      'pilePointCode': kode,
      'projectID': 64,
      'status': status,
      'depthM': depthM,
      'startAt': startAt,
      'endAt': endAt,
      'byName': 'Alif',
      'operatorName': 'Royan',
    };

Map<String, Object?> cor({
  required String kode,
  String? endAt,
  String? startAt,
  String status = 'selesai',
  int trucks = 6,
  Object? volumeM3 = 21.71,
}) =>
    {
      'pilePointCode': kode,
      'projectID': 64,
      'status': status,
      'trucks': trucks,
      'volumeM3': volumeM3,
      'startAt': startAt,
      'endAt': endAt,
      'byName': 'Alif',
    };

void main() {
  final kini = DateTime(2026, 10, 19, 12);

  test('kemarin dibuang, hari ini disimpan', () {
    // Diubah dari "24 jam bergulir" ke "hari ini" (Daniel, 19 Okt 2026).
    // Bedanya terasa pagi hari: jendela bergulir masih memuat pekerjaan
    // kemarin sore, dan "hari ini" yang memuat kemarin membuat orang salah
    // hitung.
    final h = susunKegiatan({
      'drilling': [
        bor(kode: 'KEMARIN-MALAM', endAt: '2026-10-18T23:59:00'),
        bor(kode: 'DINI-HARI', endAt: '2026-10-19T00:01:00'),
      ],
      'casting': const [],
    }, kini);
    expect(h.map((x) => x.kode), ['DINI-HARI']);
  });

  test('tanpa jam sama sekali DILEWATI, bukan ditaruh di pucuk', () {
    // Kegiatan tanpa jam tidak dapat diurutkan maupun dinyatakan masuk
    // rentang; menaruhnya paling atas akan menyesatkan.
    final h = susunKegiatan({
      'drilling': [bor(kode: 'TANPA-JAM')],
      'casting': const [],
    }, kini);
    expect(h, isEmpty);
  });

  test('startAt dipakai bila endAt kosong — log yang masih jalan', () {
    final h = susunKegiatan({
      'drilling': [bor(kode: 'JALAN', startAt: '2026-10-19T08:00:00', status: 'berjalan')],
      'casting': const [],
    }, kini);
    expect(h.single.kode, 'JALAN');
    expect(h.single.selesai, isFalse);
  });

  test('terbaru di atas, bor dan cor bercampur menurut jam', () {
    final h = susunKegiatan({
      'drilling': [bor(kode: 'B-PAGI', endAt: '2026-10-19T08:17:00')],
      'casting': [
        cor(kode: 'C-SIANG', endAt: '2026-10-19T10:45:00'),
        cor(kode: 'C-SUBUH', endAt: '2026-10-19T05:30:00'),
      ],
    }, kini);
    expect(h.map((x) => x.kode), ['C-SIANG', 'B-PAGI', 'C-SUBUH']);
  });

  test('angka bor dan cor ditulis lengkap dengan satuannya', () {
    final h = susunKegiatan({
      'drilling': [bor(kode: 'A', endAt: '2026-10-19T08:00:00')],
      'casting': [cor(kode: 'B', endAt: '2026-10-19T09:00:00')],
    }, kini);
    final b = h.firstWhere((x) => x.kode == 'B');
    final a = h.firstWhere((x) => x.kode == 'A');
    expect(a.utama, contains('m'));
    expect(b.utama, contains('6 TM'));
    expect(b.utama, contains('m³'));
  });

  test('kedalaman kosong tidak menjadi nol', () {
    // Nol berarti "belum dibor sedalam apa pun"; kosong berarti "tidak
    // tercatat". Keduanya tidak boleh terbaca sama.
    final h = susunKegiatan({
      'drilling': [bor(kode: 'A', endAt: '2026-10-19T08:00:00', depthM: null)],
      'casting': const [],
    }, kini);
    expect(h.single.utama, '—');
  });

  test('jawaban kosong atau tanpa kunci tidak melempar', () {
    expect(susunKegiatan(const {}, kini), isEmpty);
    expect(susunKegiatan(const {'drilling': [], 'casting': []}, kini), isEmpty);
  });

  test('tengah malam adalah batasnya, bukan jam sekarang', () {
    final h = susunKegiatan({
      'drilling': [
        bor(kode: 'TEPAT-TENGAH-MALAM', endAt: '2026-10-19T00:00:00'),
        bor(kode: 'SEDETIK-SEBELUM', endAt: '2026-10-18T23:59:59'),
      ],
      'casting': const [],
    }, kini);
    expect(h.map((x) => x.kode), ['TEPAT-TENGAH-MALAM']);
  });

  test('satuan tidak ditulis dua kali', () {
    // "14,00 m m" dan "21,66 m m³" — dilaporkan Daniel 19 Okt 2026.
    final h = susunKegiatan({
      'drilling': [bor(kode: 'A', endAt: '2026-10-19T08:00:00')],
      'casting': [cor(kode: 'B', endAt: '2026-10-19T09:00:00')],
    }, kini);
    for (final k in h) {
      expect(k.utama, isNot(contains('m m')));
      expect(RegExp(r'm.*m\u00B3').hasMatch(k.utama), isFalse);
    }
  });
}
