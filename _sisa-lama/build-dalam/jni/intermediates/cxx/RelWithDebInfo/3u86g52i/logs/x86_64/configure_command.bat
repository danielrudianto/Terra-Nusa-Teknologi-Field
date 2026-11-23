@echo off
"C:\\Users\\danie\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\cmake.exe" ^
  "-HC:\\Users\\danie\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev\\jni-1.1.0\\src" ^
  "-DCMAKE_SYSTEM_NAME=Android" ^
  "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON" ^
  "-DCMAKE_SYSTEM_VERSION=21" ^
  "-DANDROID_PLATFORM=android-21" ^
  "-DANDROID_ABI=x86_64" ^
  "-DCMAKE_ANDROID_ARCH_ABI=x86_64" ^
  "-DANDROID_NDK=C:\\Users\\danie\\AppData\\Local\\Android\\sdk\\ndk\\28.2.13676358" ^
  "-DCMAKE_ANDROID_NDK=C:\\Users\\danie\\AppData\\Local\\Android\\sdk\\ndk\\28.2.13676358" ^
  "-DCMAKE_TOOLCHAIN_FILE=C:\\Users\\danie\\AppData\\Local\\Android\\sdk\\ndk\\28.2.13676358\\build\\cmake\\android.toolchain.cmake" ^
  "-DCMAKE_MAKE_PROGRAM=C:\\Users\\danie\\AppData\\Local\\Android\\Sdk\\cmake\\3.22.1\\bin\\ninja.exe" ^
  "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY=D:\\Repos\\Terra-Nusa-Teknologi-Field\\Terra-Nusa-Teknologi-Field\\build\\jni\\intermediates\\cxx\\RelWithDebInfo\\3u86g52i\\obj\\x86_64" ^
  "-DCMAKE_RUNTIME_OUTPUT_DIRECTORY=D:\\Repos\\Terra-Nusa-Teknologi-Field\\Terra-Nusa-Teknologi-Field\\build\\jni\\intermediates\\cxx\\RelWithDebInfo\\3u86g52i\\obj\\x86_64" ^
  "-DCMAKE_BUILD_TYPE=RelWithDebInfo" ^
  "-BC:\\Users\\danie\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev\\jni-1.1.0\\android\\.cxx\\RelWithDebInfo\\3u86g52i\\x86_64" ^
  -GNinja
