import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../util/format.dart';
import 'photo_stamp.dart';

/// Size limits per photo kind, after compression.
///
/// The server accepts 200 kB at most. Face and attendance photos can be small;
/// the TM ticket is allowed to be larger because its figures must be legible
/// when checked at the office.
const _targets = {
  'wajah': (width: 720, kb: 60),
  'absen_masuk': (width: 1024, kb: 80),
  'absen_pulang': (width: 1024, kb: 80),
  'tiket_tm': (width: 1400, kb: 160),
};

/// Album the stamped copies go to in the phone's gallery.
const galleryAlbum = 'TerraBot Field';

/// What happened to the gallery copy — shown to the foreman in a snackbar.
enum GalleryCopy { notRequested, saved, denied, failed }

class SavedPhoto {
  const SavedPhoto({
    required this.uuid,
    required this.path,
    required this.faceCount,
    required this.sizeBytes,
    this.gallery = GalleryCopy.notRequested,
  });

  final String uuid;
  final String path;
  final int? faceCount;
  final int sizeBytes;
  final GalleryCopy gallery;
}

/// Take a photo with the camera, compress it, count faces, and save it to the queue.
///
/// * [caption] — when given, a Timemark-style caption is burned into the
///   photo. It is called AFTER the shot with the capture time, so it can wait
///   for the GPS fix that was started alongside the camera.
/// * [saveToGallery] — also put the (stamped) photo in the phone gallery,
///   album [galleryAlbum]. A failure there never fails the photo itself; the
///   outcome is reported in [SavedPhoto.gallery].
///
/// Null if the foreman cancels the camera. Any other error is thrown.
Future<SavedPhoto?> takePhoto({
  required AppDatabase db,
  required int userId,
  required String kind,
  bool frontCamera = false,
  bool countFaces = false,
  double? lat,
  double? lng,
  Future<StampCaption> Function(DateTime takenAt)? caption,
  bool saveToGallery = false,
}) async {
  final raw = await ImagePicker().pickImage(
    source: ImageSource.camera,
    preferredCameraDevice: frontCamera ? CameraDevice.front : CameraDevice.rear,
    maxWidth: 2000,
    imageQuality: 90,
  );
  if (raw == null) return null;
  final takenAt = DateTime.now();

  // Faces are counted on the ORIGINAL photo, before compression: in a small photo, the
  // faces of crew in the back row are already too small to be detected.
  int? faceCount;
  if (countFaces) faceCount = await _countFaces(raw.path);

  final target = _targets[kind] ?? (width: 1024, kb: 80);
  final Uint8List bytes;
  if (caption == null) {
    bytes = await _compress(raw.path, target.width, target.kb * 1024);
  } else {
    // Re-encode first at the target width: this applies the EXIF rotation, so
    // the caption is drawn along the bottom of the picture as the foreman
    // held the phone, not along the sensor's side.
    final upright = await FlutterImageCompress.compressWithFile(
      raw.path,
      minWidth: target.width,
      minHeight: target.width,
      quality: 95,
      format: CompressFormat.jpeg,
    );
    if (upright == null) throw StateError('Foto tidak dapat dibaca.');
    final stamped = await stampPhoto(upright, await caption(takenAt));
    bytes = await _compressBytes(stamped, target.width, target.kb * 1024);
  }

  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'foto'));
  await dir.create(recursive: true);
  final uuid = newUuid();
  final dest = p.join(dir.path, '$uuid.jpg');
  await File(dest).writeAsBytes(bytes, flush: true);
  try {
    await File(raw.path).delete();
  } catch (_) {}

  await db.insertPhoto(
    PhotosCompanion.insert(
      uuid: uuid,
      kind: kind,
      path: dest,
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      faceCount: Value(faceCount),
      takenAt: takenAt,
      lat: Value(lat),
      lng: Value(lng),
      userId: userId,
    ),
  );
  final gallery = saveToGallery ? await _copyToGallery(bytes, '${kind}_$uuid') : GalleryCopy.notRequested;
  return SavedPhoto(uuid: uuid, path: dest, faceCount: faceCount, sizeBytes: bytes.length, gallery: gallery);
}

Future<GalleryCopy> _copyToGallery(Uint8List bytes, String name) async {
  try {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      return GalleryCopy.denied;
    }
    await Gal.putImageBytes(bytes, album: galleryAlbum, name: name);
    return GalleryCopy.saved;
  } catch (_) {
    return GalleryCopy.failed;
  }
}

Future<int?> _countFaces(String path) async {
  final detector = FaceDetector(
    options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.05),
  );
  try {
    final faces = await detector.processImage(InputImage.fromFilePath(path));
    return faces.length;
  } catch (_) {
    return null; // does not block attendance; the server flags it if needed
  } finally {
    await detector.close();
  }
}

/// Same as [_compress], for bytes already in memory (the stamped PNG).
Future<Uint8List> _compressBytes(Uint8List image, int width, int maxBytes) async {
  Uint8List? result;
  var w = width;
  for (var round = 0; round < 4; round++) {
    for (final quality in const [80, 70, 60, 50, 40]) {
      result = await FlutterImageCompress.compressWithList(
        image,
        minWidth: w,
        minHeight: w,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.length <= maxBytes) return result;
    }
    w = (w * 0.75).round();
  }
  if (result == null) throw StateError('Foto tidak dapat dikompres.');
  return result;
}

/// Lower the quality, then the width, until it is under the limit.
Future<Uint8List> _compress(String path, int width, int maxBytes) async {
  Uint8List? result;
  var w = width;
  for (var round = 0; round < 4; round++) {
    for (final quality in const [80, 70, 60, 50, 40]) {
      result = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: w,
        minHeight: w,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result != null && result.length <= maxBytes) return result;
    }
    w = (w * 0.75).round();
  }
  if (result == null) throw StateError('Foto tidak dapat dikompres.');
  return result;
}
