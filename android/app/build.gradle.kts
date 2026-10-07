// Ditulis tangan, BUKAN dari `flutter create`.
//
// `flutter create .` tidak menimpa berkas yang sudah ada, jadi berkas ini
// tetap dipakai setelah folder android/ lainnya dibuat. Isinya = templat
// Flutter 3.47 ditambah dua hal yang wajib untuk TerraBot Field:
//
//   1. Desugaring pustaka inti Java — diminta flutter_local_notifications
//      (notifikasi stopwatch pengecoran). Tanpa ini build GAGAL.
//   2. minSdk 24 — batas bawah flutter_secure_storage 11 (dan Flutter 3.35+
//      sendiri). Android 7.0 ke atas.

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    buildTypes {
        release {
            // TODO: tanda tangan rilis sendiri sebelum APK dibagikan ke
            // lapangan (lihat BACA-DULU.md, bagian "APK rilis").
            signingConfig = signingConfigs.getByName("debug")
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
