import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:terrabot_field/core/device/location.dart';
import 'package:terrabot_field/features/attendance/attendance_stamp.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id'));

  const project = {
    'code': 'R501',
    'name': 'Konstruksi Secant Pile area R501',
    'latitude': '-6.9000000',
    'longitude': '107.6000000',
    'geofenceRadiusM': 200,
  };

  group('zoneLabel', () {
    test('Indonesian zones by offset', () {
      expect(zoneLabel(const Duration(hours: 7)), 'WIB');
      expect(zoneLabel(const Duration(hours: 8)), 'WITA');
      expect(zoneLabel(const Duration(hours: 9)), 'WIT');
    });

    test('a foreign zone is shown, not passed off as WIB', () {
      expect(zoneLabel(const Duration(hours: -4)), 'UTC-4');
    });
  });

  group('attendanceCaption', () {
    test('inside the radius: kind, project, address, coordinates, distance, foreman', () {
      final c = attendanceCaption(
        at: DateTime(2026, 10, 8, 7, 12),
        isCheckIn: true,
        project: project,
        point: const GeoPoint(lat: -6.9005, lng: 107.6, accuracyM: 8.4, mocked: false),
        address: 'Jl. Parahyangan Raya, Padalarang',
        locationProblem: null,
        userName: 'Asep',
      );
      expect(c.headline, startsWith('07:12'));
      expect(c.lines, contains('ABSEN MASUK · R501 Konstruksi Secant Pile area R501'));
      expect(c.lines, contains('Jl. Parahyangan Raya, Padalarang'));
      expect(c.lines, contains('-6.900500, 107.600000 (±8 m)'));
      expect(c.lines.any((l) => l.startsWith('56 m dari lokasi proyek')), isTrue);
      expect(c.lines.any((l) => l.contains('DI LUAR RADIUS')), isFalse);
      expect(c.lines.last, 'Diabsen oleh: Asep · TerraBot Field');
    });

    test('outside the radius and mocked GPS are spelled out on the photo', () {
      final c = attendanceCaption(
        at: DateTime(2026, 10, 8, 17, 5),
        isCheckIn: false,
        project: project,
        point: const GeoPoint(lat: -6.92, lng: 107.6, accuracyM: 30, mocked: true),
        address: null,
        locationProblem: null,
        userName: 'Asep',
      );
      expect(c.lines[1], startsWith('ABSEN PULANG'));
      expect(c.lines.any((l) => l.contains('DI LUAR RADIUS')), isTrue);
      expect(c.lines, contains('PERINGATAN: lokasi palsu terdeteksi'));
    });

    test('no GPS: the reason is printed instead of coordinates', () {
      final c = attendanceCaption(
        at: DateTime(2026, 10, 8, 7, 0),
        isCheckIn: true,
        project: project,
        point: null,
        address: null,
        locationProblem: 'Sinyal GPS tidak didapat dalam 20 detik.',
        userName: 'Asep',
      );
      expect(c.lines, contains('Tanpa GPS: Sinyal GPS tidak didapat dalam 20 detik.'));
    });
  });
}
