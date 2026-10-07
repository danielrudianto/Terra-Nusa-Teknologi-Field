import 'dart:async';

import 'package:geolocator/geolocator.dart';

class TitikLokasi {
  const TitikLokasi({required this.lat, required this.lng, required this.akurasiM, required this.palsu});

  final double lat;
  final double lng;
  final double akurasiM;

  /// Android melaporkan lokasi dari aplikasi "lokasi palsu". Dikirim apa
  /// adanya; server yang memberi tanda GPS_PALSU, HP tidak menolak absen.
  final bool palsu;

  Map<String, Object?> keKejadian() => {
        'lat': lat.toStringAsFixed(7),
        'lng': lng.toStringAsFixed(7),
        'accuracyM': akurasiM.toStringAsFixed(1),
        'isMocked': palsu,
      };
}

class HasilLokasi {
  const HasilLokasi({this.titik, this.masalah});

  final TitikLokasi? titik;

  /// Mengapa lokasi tidak didapat — ditampilkan di banner. Absen TETAP
  /// boleh disimpan tanpa lokasi (server menandai TANPA_LOKASI); di basement
  /// atau di bawah bekisting, GPS memang sering tidak dapat.
  final String? masalah;
}

/// Ambil lokasi sekali. Tidak pernah melempar galat.
Future<HasilLokasi> ambilLokasi() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const HasilLokasi(masalah: 'GPS HP mati. Nyalakan Lokasi di pengaturan cepat.');
    }
    var izin = await Geolocator.checkPermission();
    if (izin == LocationPermission.denied) izin = await Geolocator.requestPermission();
    if (izin == LocationPermission.denied) {
      return const HasilLokasi(masalah: 'Izin lokasi ditolak.');
    }
    if (izin == LocationPermission.deniedForever) {
      return const HasilLokasi(masalah: 'Izin lokasi ditolak permanen. Buka Pengaturan → Aplikasi → TerraBot Field → Izin.');
    }

    Position? p;
    try {
      p = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      p = await Geolocator.getLastKnownPosition();
    }
    if (p == null) {
      return const HasilLokasi(masalah: 'Sinyal GPS tidak didapat dalam 20 detik.');
    }
    return HasilLokasi(
      titik: TitikLokasi(lat: p.latitude, lng: p.longitude, akurasiM: p.accuracy, palsu: p.isMocked),
    );
  } catch (e) {
    return HasilLokasi(masalah: 'Lokasi gagal dibaca: $e');
  }
}
