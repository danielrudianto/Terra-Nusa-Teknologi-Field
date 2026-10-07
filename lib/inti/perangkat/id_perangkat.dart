import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../util/format.dart';

const _kunci = 'id_perangkat';

/// Pengenal HP ini — dibuat SEKALI saat aplikasi pertama dibuka, dikirim
/// di header `X-Device-Id` pada setiap permintaan.
///
/// Server memakainya untuk dua hal: memblokir HP yang hilang, dan
/// mengenali bahwa refresh token lama yang datang lagi berasal dari HP yang
/// sama yang jawabannya hilang di jalan (bukan pencuri).
Future<String> idPerangkat(FlutterSecureStorage simpan) async {
  final ada = await simpan.read(key: _kunci);
  if (ada != null && ada.isNotEmpty) return ada;
  final baru = uuidBaru();
  await simpan.write(key: _kunci, value: baru);
  return baru;
}
