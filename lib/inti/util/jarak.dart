import 'dart:math' as math;

/// Jarak dua titik di permukaan bumi (haversine), meter.
///
/// Sama dengan `jarak_meter` di server (`utils/field_hitung.py`). Di HP
/// hanya untuk BANNER ("Anda 340 m dari lokasi proyek") — angka yang
/// tercatat tetap hitungan server, karena HP dapat diakali.
double jarakMeter(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}
