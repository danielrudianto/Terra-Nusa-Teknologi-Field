import 'package:dio/dio.dart';

import '../util/error_reporter.dart';

/// Error from the server in a displayable form.
///
/// The TerraBot server sends `detail` as a `{code, message}` object for coded
/// errors, or as text for legacy errors. Both are read here.
class ApiError implements Exception {
  ApiError({required this.message, this.status, this.code, this.context, this.offline = false});

  final String message;
  final int? status;
  final String? code;

  /// `detail.context` of a coded error (e.g. `minVersion`, `downloadUrl`).
  final Map<String, Object?>? context;

  /// The server no longer serves this app version (HTTP 426).
  bool get appOutdated => code == 'APP_KEDALUWARSA' || status == 426;

  /// Never reached the server at all (no signal, timeout).
  final bool offline;

  bool get sessionExpired => status == 401;

  factory ApiError.from(Object e) {
    if (e is ApiError) return e;
    if (e is DioException) {
      final r = e.response;
      if (r == null) {
        return ApiError(
          message: 'Tidak dapat terhubung ke server. Periksa sinyal.',
          offline: true,
        );
      }
      final data = r.data;
      String message = 'Server menjawab ${r.statusCode}.';
      String? code;
      Map<String, Object?>? context;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is Map) {
          message = (detail['message'] ?? message).toString();
          code = detail['code']?.toString();
          if (detail['context'] case final Map c) context = c.cast<String, Object?>();
        } else if (detail is String) {
          message = detail;
        }
      }
      final galat = ApiError(
        message: message,
        status: r.statusCode,
        code: code,
        context: context,
      );

      /*
       * DICATAT DI SINI, satu titik untuk seluruh galat server.
       *
       * Setiap galat server melewati pabrik ini — jadi dicatat di sini,
       * semuanya ikut tanpa satu pun pemanggil disentuh. Dipasang satu per
       * satu di penangannya, yang ditambahkan bulan depan akan terlupa.
       *
       * `error-logs` SENDIRI DIKECUALIKAN: pengirimannya yang gagal akan
       * melewati pabrik ini juga, dan mencatat kegagalan pencatatan adalah
       * lingkaran yang tidak berujung.
       *
       * Yang OFFLINE tidak sampai ke sini — ia keluar lebih dulu di atas,
       * dan memang bukan kerusakan: tidak ada sinyal di lapangan adalah
       * keadaan sehari-hari, dan armada HP yang diam sudah terlihat di
       * monitoring lewat `lastSeenAt`.
       */
      final jalur = e.requestOptions.path;
      if (!jalur.contains('error-logs')) {
        ErrorReporter.record(
          code: code,
          status: r.statusCode,
          screen: jalur,
          // `expected` = aplikasinya MENGENALI penolakan ini dan punya
          // layarnya sendiri untuk itu: versi kedaluwarsa dan sesi habis.
          // Selebihnya jatuh ke kalimat apa adanya dari server, dan itu
          // yang perlu dilihat.
          expected: galat.appOutdated || galat.sessionExpired,
        );
      }

      return galat;
    }
    return ApiError(message: e.toString());
  }

  @override
  String toString() => message;
}
