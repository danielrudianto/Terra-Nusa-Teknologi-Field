import 'package:dio/dio.dart';

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
      return ApiError(message: message, status: r.statusCode, code: code, context: context);
    }
    return ApiError(message: e.toString());
  }

  @override
  String toString() => message;
}
