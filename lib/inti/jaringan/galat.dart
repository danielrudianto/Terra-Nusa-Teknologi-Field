import 'package:dio/dio.dart';

/// Galat dari server dalam bentuk yang dapat ditampilkan.
///
/// Server TerraBot mengirim `detail` sebagai objek `{code, message}` untuk
/// galat berkode, atau teks untuk galat lama. Keduanya dibaca di sini.
class GalatApi implements Exception {
  GalatApi({required this.pesan, this.status, this.kode, this.tanpaJaringan = false});

  final String pesan;
  final int? status;
  final String? kode;

  /// Tidak sampai ke server sama sekali (tanpa sinyal, waktu habis).
  final bool tanpaJaringan;

  bool get sesiHabis => status == 401;

  factory GalatApi.dari(Object e) {
    if (e is GalatApi) return e;
    if (e is DioException) {
      final r = e.response;
      if (r == null) {
        return GalatApi(
          pesan: 'Tidak dapat terhubung ke server. Periksa sinyal.',
          tanpaJaringan: true,
        );
      }
      final data = r.data;
      String pesan = 'Server menjawab ${r.statusCode}.';
      String? kode;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          pesan = (detail['message'] ?? pesan).toString();
          kode = detail['code']?.toString();
        } else if (detail is String) {
          pesan = detail;
        }
      }
      return GalatApi(pesan: pesan, status: r.statusCode, kode: kode);
    }
    return GalatApi(pesan: e.toString());
  }

  @override
  String toString() => pesan;
}
