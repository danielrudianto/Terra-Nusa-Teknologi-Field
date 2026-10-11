import '../../core/device/location.dart';
import '../../core/device/photo_stamp.dart';
import '../../core/util/distance.dart';
import '../../core/util/format.dart';

/// Indonesian time-zone label for a UTC offset: WIB / WITA / WIT.
///
/// Other offsets (a phone set to a foreign zone) print as UTC+h so the odd
/// setting is visible on the photo instead of silently passing as WIB.
String zoneLabel(Duration offset) => switch (offset.inMinutes) {
      420 => 'WIB',
      480 => 'WITA',
      540 => 'WIT',
      _ => 'UTC${offset.isNegative ? '-' : '+'}${offset.inHours.abs()}',
    };

/// Caption for an attendance photo. Pure, so it can be unit-tested.
///
/// Text is Indonesian — it is read by foremen, office staff and anyone the
/// photo is forwarded to on WhatsApp.
StampCaption attendanceCaption({
  required DateTime at,
  required bool isCheckIn,
  required Map<String, Object?>? project,
  required GeoPoint? point,
  required String? address,
  required String? locationProblem,
  required String userName,
}) {
  final local = at.toLocal();
  final lines = <String>[
    longDate(local),
    '${isCheckIn ? 'ABSEN MASUK' : 'ABSEN PULANG'} · '
        '${project == null ? 'Proyek tidak dikenal' : '${project['code']} ${project['name']}'}',
  ];

  if (point == null) {
    lines.add('Tanpa GPS${locationProblem == null ? '' : ': $locationProblem'}');
  } else {
    if (address != null && address.isNotEmpty) lines.add(address);
    lines.add('${point.lat.toStringAsFixed(6)}, ${point.lng.toStringAsFixed(6)} (±${point.accuracyM.round()} m)');
    final projectLat = toDoubleOrNull(project?['latitude']);
    final projectLng = toDoubleOrNull(project?['longitude']);
    if (projectLat != null && projectLng != null) {
      final d = distanceMeters(point.lat, point.lng, projectLat, projectLng).round();
      final radius = toDoubleOrNull(project?['geofenceRadiusM']) ?? 200;
      lines.add(d <= radius ? '$d m dari lokasi proyek' : '$d m dari lokasi proyek — DI LUAR RADIUS');
    }
    if (point.mocked) lines.add('PERINGATAN: lokasi palsu terdeteksi');
  }
  lines.add('Diabsen oleh: $userName · TerraBot Field');

  return StampCaption(
    headline: '${formatTime(local)} ${zoneLabel(local.timeZoneOffset)}',
    lines: lines,
  );
}
