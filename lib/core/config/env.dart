import 'package:package_info_plus/package_info_plus.dart';

/// Configuration read at build time (`--dart-define`).
///
///     flutter run --dart-define=API_URL=http://10.0.2.2:7500
///     flutter build apk --dart-define=API_URL=https://services.terrabot.alphakonstruksi.id
class Env {
  Env._();

  /// Address of the TerraBot backend — the SAME server as the web app.
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://services.terrabot.alphakonstruksi.id',
  );

  /// Also sent in the `X-App-Version` header; recorded in `field_devices`
  /// and `field_sync_receipts`, so that "my data didn't arrive" can be
  /// matched to the app version. The server refuses versions older than
  /// its `FIELD_MIN_APP_VERSION`.
  ///
  /// Read from the installed package (`version:` in pubspec.yaml) by
  /// [loadVersion], so it can never lag behind the APK — a forgotten
  /// `--dart-define` would otherwise report 0.1.0 forever and get the phone
  /// locked out. The define, if given, is only the fallback.
  static String get appVersion => _appVersion;
  static String _appVersion = const String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

  /// Called once by `AppContext.open()`, before anything talks to the server.
  ///
  /// NOMOR BUILD IKUT — `1.0.12+28`, bukan `1.0.12`.
  ///
  /// Ketahuan 19 Oktober 2026: server membandingkan EMPAT angka
  /// (`urai_versi`, nomor build ikut dihitung sejak 14 Okt), sementara HP
  /// hanya mengirim `info.version` yaitu versionName tanpa build. Jadi HP
  /// yang SUDAH memasang 1.0.12+27 mengirim `1.0.12` -> (1,0,12,0),
  /// dibandingkan dengan `FIELD_LATEST_APP_VERSION=1.0.12+27` ->
  /// (1,0,12,27), dan terus-menerus diajak memperbarui ke versi yang sudah
  /// terpasang di HP itu sendiri. Ajakan yang tidak dapat dipenuhi adalah
  /// ajakan yang mengajari kru mengabaikan ajakan.
  ///
  /// Akibat kedua yang sama buruknya: `FIELD_MIN_APP_VERSION` tidak dapat
  /// membedakan dua rilis yang versionName-nya sama — padahal itu justru
  /// bentuk rilis yang paling sering dibuat.
  ///
  /// `buildNumber` dapat kosong pada sebagian platform; kalau kosong,
  /// kirim versionName saja, jangan `1.0.12+` yang tidak terurai.
  static Future<void> loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isEmpty) return;
      final build = info.buildNumber.trim();
      _appVersion = build.isEmpty ? info.version : '${info.version}+$build';
    } catch (_) {
      // Tests / no platform: keep the fallback.
    }
  }

  /// Server limit: 50 items per push (see `SyncPushBody`).
  static const int itemsPerPush = 50;
}
