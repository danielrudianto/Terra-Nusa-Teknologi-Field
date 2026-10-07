import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../util/format.dart';

/// Batas ukuran per jenis foto, sesudah dikompres.
///
/// Server menerima paling besar 200 kB. Wajah dan absen cukup kecil;
/// tiket TM dibiarkan lebih besar karena angkanya harus terbaca saat
/// diperiksa di kantor.
const _sasaran = {
  'wajah': (lebar: 720, kb: 60),
  'absen_masuk': (lebar: 1024, kb: 80),
  'absen_pulang': (lebar: 1024, kb: 80),
  'tiket_tm': (lebar: 1400, kb: 160),
};

class FotoTersimpan {
  const FotoTersimpan({required this.uuid, required this.path, required this.jumlahWajah, required this.ukuran});

  final String uuid;
  final String path;
  final int? jumlahWajah;
  final int ukuran;
}

/// Ambil foto dengan kamera, kompres, hitung wajah, dan simpan ke antrean.
///
/// Null bila mandor membatalkan kamera. Galat lain dilempar.
Future<FotoTersimpan?> ambilFoto({
  required BasisData db,
  required int userId,
  required String jenis,
  bool kameraDepan = false,
  bool hitungWajah = false,
  double? lat,
  double? lng,
}) async {
  final mentah = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: kameraDepan ? CameraDevice.front : CameraDevice.rear,
    maxWidth: 2000,
    imageQuality: 90,
  );
  if (mentah == null) return null;
  final diambil = DateTime.now();

  // Wajah dihitung pada foto ASLI, sebelum dikompres: di foto kecil, wajah
  // kru di baris belakang sudah terlalu kecil untuk terdeteksi.
  int? jumlahWajah;
  if (hitungWajah) jumlahWajah = await _hitungWajah(mentah.path);

  final s = _sasaran[jenis] ?? (lebar: 1024, kb: 80);
  final isi = await _kompres(mentah.path, s.lebar, s.kb * 1024);

  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'foto'));
  await dir.create(recursive: true);
  final uuid = uuidBaru();
  final tujuan = p.join(dir.path, '$uuid.jpg');
  await File(tujuan).writeAsBytes(isi, flush: true);
  try {
    await File(mentah.path).delete();
  } catch (_) {}

  await db.simpanFoto(
    FotoCompanion.insert(
      uuid: uuid,
      jenis: jenis,
      path: tujuan,
      sha256: sha256.convert(isi).toString(),
      ukuran: isi.length,
      jumlahWajah: Value(jumlahWajah),
      diambil: diambil,
      lat: Value(lat),
      lng: Value(lng),
      userId: userId,
    ),
  );
  return FotoTersimpan(uuid: uuid, path: tujuan, jumlahWajah: jumlahWajah, ukuran: isi.length);
}

Future<int?> _hitungWajah(String path) async {
  final pendeteksi = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.05),
  );
  try {
    final wajah = await pendeteksi.processImage(InputImage.fromFilePath(path));
    return wajah.length;
  } catch (_) {
    return null; // tidak menghalangi absen; server menandainya bila perlu
  } finally {
    await pendeteksi.close();
  }
}

/// Turunkan mutu, lalu lebar, sampai di bawah batas.
Future<Uint8List> _kompres(String path, int lebar, int batas) async {
  Uint8List? hasil;
  var w = lebar;
  for (var putaran = 0; putaran < 4; putaran++) {
    for (final mutu in const [80, 70, 60, 50, 40]) {
      hasil = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: w,
        minHeight: w,
        quality: mutu,
        format: CompressFormat.jpeg,
      );
      if (hasil != null && hasil.length <= batas) return hasil;
    }
    w = (w * 0.75).round();
  }
  if (hasil == null) throw StateError('Foto tidak dapat dikompres.');
  return hasil;
}
