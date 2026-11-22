import 'package:flutter_test/flutter_test.dart';
import 'package:terrabot_field/core/sync/office_notice.dart';

/// Kabar kantor (log dihapus / dibetulkan) disimpan di meta sebagai teks dan
/// dibaca ulang oleh layar log. Rusak di sini = layar kembali diam saat
/// catatannya dihapus, persis keluhan 22 Nov 2026.
void main() {
  test('pulang-pergi utuh', () {
    final k = OfficeNotice(at: DateTime.parse('2026-11-22T09:40:00+07:00'), oleh: 'Ade', catatan: 'Alasan: salah titik');
    final b = OfficeNotice.decode(k.encode())!;
    expect(b.oleh, 'Ade');
    expect(b.catatan, 'Alasan: salah titik');
    expect(b.at, DateTime.parse('2026-11-22T09:40:00+07:00'));
  });

  test('kosong atau rusak = tidak ada kabar, bukan galat', () {
    expect(OfficeNotice.decode(null), isNull);
    expect(OfficeNotice.decode(''), isNull);
    expect(OfficeNotice.decode('{bukan json'), isNull);
  });

  test('tanpa jam dan nama tetap terbaca', () {
    final b = OfficeNotice.decode(const OfficeNotice().encode())!;
    expect(b.at, isNull);
    expect(b.oleh, isNull);
  });

  test('kunci per uuid tidak bertabrakan antara hapus dan betulkan', () {
    expect(officeDeletedKey('a'), isNot(officeEditedKey('a')));
  });
}
