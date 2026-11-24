import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../i18n.dart';

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng, required this.accuracyM, required this.mocked});

  final double lat;
  final double lng;
  final double accuracyM;

  /// Android reports a location coming from a "mock location" app. Sent as
  /// is; the server sets the GPS_PALSU flag, the phone does not refuse the attendance.
  final bool mocked;

  Map<String, Object?> toEvent() => {
        'lat': lat.toStringAsFixed(7),
        'lng': lng.toStringAsFixed(7),
        'accuracyM': accuracyM.toStringAsFixed(1),
        'isMocked': mocked,
      };
}

class LocationResult {
  const LocationResult({this.point, this.problem});

  final GeoPoint? point;

  /// Why the location could not be obtained — shown in the banner. Attendance CAN
  /// still be saved without a location (the server flags TANPA_LOKASI); in a basement
  /// or under formwork, GPS often simply cannot get a fix.
  final String? problem;
}

/// The app's language, or Indonesian before the first screen is built.
AppLocalizations get _l => L10n.current ?? lookupAppLocalizations(const Locale('id'));

/// Get the location once. Never throws an error.
Future<LocationResult> getLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationResult(problem: _l.locGpsOff);
    }
    var permissions = await Geolocator.checkPermission();
    if (permissions == LocationPermission.denied) permissions = await Geolocator.requestPermission();
    if (permissions == LocationPermission.denied) {
      return LocationResult(problem: _l.locDenied);
    }
    if (permissions == LocationPermission.deniedForever) {
      return LocationResult(problem: _l.locDeniedForever);
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
      return LocationResult(problem: _l.locNoSignal);
    }
    return LocationResult(
      point: GeoPoint(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy, mocked: p.isMocked),
    );
  } catch (e) {
    return LocationResult(problem: _l.locFailed('$e'));
  }
}

/// Street-level address for the photo caption, e.g. "Jl. Raya Bogor, Cimanggis, Depok".
///
/// Uses Android's geocoder, which needs a signal. Null when offline, slow
/// (4 s cap — the foreman is waiting on the camera screen) or unknown; the
/// caption then shows only the coordinates. Never throws.
Future<String?> addressFor(GeoPoint point) async {
  try {
    final places = await Geocoding(locale: const Locale('id', 'ID'))
        .placemarkFromCoordinates(point.lat, point.lng)
        .timeout(const Duration(seconds: 4));
    if (places.isEmpty) return null;
    final p = places.first;
    final parts = <String>[];
    for (final v in [p.street ?? p.thoroughfare, p.subLocality, p.locality ?? p.subAdministrativeArea]) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
    }
    return parts.isEmpty ? null : parts.join(', ');
  } catch (_) {
    return null;
  }
}
