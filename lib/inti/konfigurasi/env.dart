/// Konfigurasi yang dibaca saat build (`--dart-define`).
///
///     flutter run --dart-define=API_URL=http://10.0.2.2:7500
///     flutter build apk --dart-define=API_URL=https://services.terrabot.alphakonstruksi.id
class Env {
  Env._();

  /// Alamat backend TerraBot — server yang SAMA dengan web.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://services.terrabot.alphakonstruksi.id',
  );

  /// Ikut dikirim di header `X-App-Version`; tercatat di `field_devices`
  /// dan `field_sync_receipts`, supaya "data saya tidak masuk" dapat
  /// dicocokkan dengan versi aplikasinya.
  static const String versiAplikasi = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// Batas server: 50 item per kiriman (lihat `SyncPushBody`).
  static const int itemPerKiriman = 50;
}
