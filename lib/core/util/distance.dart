import 'dart:math' as math;

/// Distance between two points on the Earth's surface (haversine), in meters.
///
/// Same as `jarak_meter` on the server (`utils/field_hitung.py`). On the phone
/// it is only for the BANNER ("You are 340 m from the project site") — the number
/// that gets recorded is still the server's calculation, because a phone can be gamed.
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}
