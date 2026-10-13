import 'package:device_info_plus/device_info_plus.dart';

/// Nama HP ini sebagaimana pemiliknya mengenalinya — "Samsung SM-A556E".
///
/// Dikirim sebagai header `X-Device-Name`, dan server memakainya untuk menamai
/// perangkat pada peringatan "akun ini dipakai di HP lain". Tanpa ini yang
/// tampil adalah user-agent bawaan Dart, yang berbunyi "Dart/3.13 (dart:io)" di
/// SEMUA HP — pesan yang tidak menolong siapa pun memilih HP mana yang harus
/// dikeluarkan.
///
/// Gagal membacanya tidak pernah boleh menggagalkan apa pun: tanpa nama,
/// server kembali memakai user-agent, jelek tetapi tetap jalan.
Future<String?> loadDeviceName() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final merek = info.manufacturer.trim();
    final tipe = info.model.trim();
    final nama = [if (merek.isNotEmpty) _berkapital(merek), if (tipe.isNotEmpty) tipe].join(' ').trim();
    if (nama.isEmpty) return null;
    // Kolom `peramban` di server 255 karakter; dipotong di sini supaya yang
    // dikirim dan yang tersimpan sama persis.
    return nama.length <= 255 ? nama : nama.substring(0, 255);
  } catch (_) {
    return null;
  }
}

/// "samsung" → "Samsung". Merek dilaporkan Android dalam huruf kecil semua.
String _berkapital(String s) => s[0].toUpperCase() + s.substring(1);
