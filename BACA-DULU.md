# TerraBot Field — langkah pertama di PC

Repo ini berisi kode Dart, plugin lokal `jam_monoton`, dan dua berkas Android
yang ditulis tangan (`android/app/build.gradle.kts`, `AndroidManifest.xml`).
Sisa folder `android/` DIBUAT oleh Flutter — langkah 2.

Kode ini BELUM PERNAH dikompilasi: di lingkungan tempat ia ditulis, Flutter
SDK tidak dapat diunduh. Sintaksnya sudah diperiksa dengan parser Dart dan
versi paketnya dicocokkan ke kode sumber rilis terbaru, tetapi galat tipe
baru akan terlihat di langkah 4. Kirim keluarannya bila ada yang merah.

## 1. Flutter

Flutter stable **3.47** atau lebih baru (`flutter --version`). Paket di
`pubspec.yaml` butuh Dart 3.12.

    flutter upgrade

## 2. Buat folder android/

Di folder repo ini:

    flutter create --org id.co.alphakonstruksi --project-name terrabot_field --platforms android .

`flutter create` TIDAK menimpa berkas yang sudah ada — `build.gradle.kts`,
`AndroidManifest.xml`, `pubspec.yaml`, dan `lib/main.dart` di repo ini tetap.
Ia juga membuat `test/widget_test.dart` berisi contoh penghitung —
**hapus berkas itu**, ia merujuk `MyApp` yang tidak ada.

    del test\widget_test.dart

## 3. Paket & kode tergenerasi

    flutter pub get
    dart run build_runner build -d

`build_runner` membuat `lib/inti/db/database.g.dart` (drift). Ulangi setiap
kali tabel di `database.dart` diubah.

## 4. Uji

    flutter analyze
    flutter test

`test/rencana_potong_test.dart` memakai angka dari prototipe Python yang
sama dengan rancangan; bila ada yang beda, rumusnya yang bergeser.

## 5. Jalankan di HP

HP Android 7.0+ dengan USB debugging:

    flutter run --dart-define=API_URL=https://services.terrabot.alphakonstruksi.id

Ke backend lokal dari emulator: `--dart-define=API_URL=http://10.0.2.2:7500`.

Akun = akun TerraBot web yang sama. Supaya menu lapangan muncul, akunnya
harus punya divisi **Field Engineer (Lapangan)** (atur di web).

## 6. APK rilis

    flutter build apk --release --dart-define=API_URL=https://services.terrabot.alphakonstruksi.id

Saat ini APK rilis DITANDATANGANI dengan kunci debug (lihat TODO di
`android/app/build.gradle.kts`). Sebelum dibagikan ke lapangan, buat
keystore sendiri — APK yang ditandatangani kunci berbeda tidak dapat
dipasang menimpa yang lama, jadi tentukan kuncinya SEBELUM rilis pertama.

## Bila build Android gagal

* `compileSdk 37 ... not found` → buka Android Studio → SDK Manager, pasang
  platform yang diminta (beberapa plugin sudah memakai SDK 37).
* `coreLibraryDesugaring` → pastikan `android/app/build.gradle.kts` masih
  berkas dari repo ini, bukan yang dibuat ulang.
