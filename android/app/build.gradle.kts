// Written by hand, NOT from `flutter create`.
//
// `flutter create .` does not overwrite existing files, so this file
// stays in use after the rest of the android/ folder is generated. Its contents =
// the Flutter 3.47 template plus two things that are mandatory for TerraBot Field:
//
//   1. Core library desugaring for Java — required by flutter_local_notifications
//      (casting stopwatch notification). Without it the build FAILS.
//   2. minSdk 24 — lower bound of flutter_secure_storage 11 (and Flutter 3.35+
//      itself). Android 7.0 and up.

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // DIDAFTARKAN, TETAPI DITERAPKAN HANYA BILA BERKASNYA ADA — lihat
    // blok `if` di bawah.
    id("com.google.gms.google-services") apply false
}

// FIREBASE DITERAPKAN HANYA BILA `google-services.json` MEMANG ADA.
//
// Plugin ini MENGGAGALKAN build kalau berkasnya tidak ada. Diterapkan
// tanpa syarat, satu repositori yang baru di-klon — mesin baru, mesin
// orang lain, pemulihan cadangan — tidak dapat membangun APK sama sekali,
// dengan galat tentang Firebase pada pekerjaan yang tidak ada
// hubungannya dengan notifikasi.
//
// Jadi sifatnya dibuat sama dengan `push_aktif()` dan `fcm_aktif()` di
// server: tanpa kuncinya, fiturnya DIAM-DIAM MATI dan sisanya jalan
// seluruhnya. `Firebase.initializeApp()` di `pesan_awan.dart` gagal,
// kegagalannya ditangkap dan dicatat, dan aplikasinya berjalan tanpa
// kabar dari server — absensi, log cor, arloji, dan pengingat utuh.
//
// `google-services.json` sendiri BUKAN rahasia: ia konfigurasi KLIEN (id
// proyek, id aplikasi, kunci API ber-pembatas) dan memang ikut di dalam
// APK yang dibagikan. Yang rahasia kunci akun layanan di SERVER — lihat
// catatan pada `utils/fcm.py` di repositori Office.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "google-services.json tidak ada: APK dibangun TANPA notifikasi dari server.",
    )
}

// Release signing key: android/key.properties + android/app/terrabot-field-release.jks.
// Both are kept OUT of git. Every release MUST be signed with this same key,
// or phones refuse to install the update over the app they have (and
// uninstalling first deletes data not yet sent). Back both files up.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "id.co.alphakonstruksi.terrabot_field"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "id.co.alphakonstruksi.terrabot_field"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // No silent fallback to the debug key. An APK signed with the debug
            // key cannot be installed over a release-signed one ("App not
            // installed"), and the only way out is uninstalling the app — which
            // deletes logs not yet sent. A release build with no key FAILS instead,
            // see the guard below.
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }
}

// Guard: a release artifact may NEVER leave this machine signed with the debug
// key. Debug builds (`flutter run`) are untouched, so a laptop without
// key.properties can still develop — it just cannot hand out an APK. Escape
// hatch for a throwaway local test: -Pizinkan-rilis-tanpa-kunci=true
val izinTanpaKunci = project.findProperty("izinkan-rilis-tanpa-kunci") == "true"
tasks.configureEach {
    if ((name.startsWith("package") || name.startsWith("sign")) && name.contains("Release")) {
        doFirst {
            if (!hasReleaseKey && !izinTanpaKunci) {
                throw GradleException(
                    "Build rilis DIBATALKAN: android/key.properties tidak ada, jadi APK/AAB ini " +
                        "akan ketandatangan kunci DEBUG. HP yang sudah memasang versi rilis akan " +
                        "menolaknya (\"App not installed\"), dan uninstall menghapus log yang belum " +
                        "terkirim. Salin key.properties + android/app/terrabot-field-release.jks ke " +
                        "mesin ini dulu (flashdisk atau 7-Zip AES-256 — JANGAN OneDrive/WhatsApp/" +
                        "email/Drive). Kalau memang hanya uji lokal: tambahkan " +
                        "-Pizinkan-rilis-tanpa-kunci=true"
                )
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
