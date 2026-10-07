import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// uuid v4 — DIBUAT HP. Inilah yang membuat kiriman ulang tidak dobel.
String uuidBaru() => _uuid.v4();

/// ISO-8601 BERZONA, mis. `2026-10-08T07:12:03.412+07:00`.
///
/// `DateTime.toIso8601String()` bawaan Dart untuk waktu lokal TIDAK menulis
/// offset sama sekali — dan server lalu harus menebak zonanya. Proyek di
/// Bali (WITA) akan tercatat sejam meleset.
String isoBerzona(DateTime t) {
  final lokal = t.toLocal();
  final offset = lokal.timeZoneOffset;
  final tanda = offset.isNegative ? '-' : '+';
  final jam = offset.inHours.abs().toString().padLeft(2, '0');
  final menit = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final dasar = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS").format(lokal);
  return '$dasar$tanda$jam:$menit';
}

/// Tanggal `yyyy-MM-dd` menurut kalender HP.
String tanggalIso(DateTime t) => DateFormat('yyyy-MM-dd').format(t.toLocal());

/// Angka untuk bidang Decimal server — dikirim sebagai TEKS, bukan double,
/// supaya 7,1 tidak sampai sebagai 7,0999999.
String angkaTeks(num nilai, {int desimal = 2}) => nilai.toStringAsFixed(desimal);

/// Angka dari JSON server (bisa teks "7.00" atau angka).
double? keDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? keInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Angka masukan pengguna: koma DAN titik diterima sebagai pemisah desimal.
double? bacaAngka(String teks) => double.tryParse(teks.trim().replaceAll(',', '.'));

final _fmtJam = DateFormat('HH:mm');
final _fmtTanggal = DateFormat('EEE, d MMM yyyy', 'id');

String jam(DateTime t) => _fmtJam.format(t.toLocal());
String tanggalPanjang(DateTime t) => _fmtTanggal.format(t.toLocal());

/// "00:14:32"
String durasi(Duration d) {
  final j = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$j:$m:$s';
}

String meter(double? v, {int desimal = 2}) =>
    v == null ? '–' : '${v.toStringAsFixed(desimal).replaceAll('.', ',')} m';
