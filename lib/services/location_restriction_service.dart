import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geo;

class LocationRestrictionService {
  // Bacoor, Cavite city bounds (Philippines, 4102)
  // OSM-derived Bacoor bounds
  static const double bacoorMinLat = 14.350387;
  static const double bacoorMaxLat = 14.475765;
  static const double bacoorMinLon = 120.923611;
  static const double bacoorMaxLon = 121.013483;
  static const String bacoorPsgc = '042103000';

  /// Check if location permission is granted
  static Future<bool> isLocationPermissionGranted() async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.always || status == LocationPermission.whileInUse;
  }

  /// Request location permission
  static Future<bool> requestLocationPermission() async {
    final status = await Geolocator.requestPermission();
    return status == LocationPermission.always || status == LocationPermission.whileInUse;
  }

  /// Get current position
  static Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      bool hasPermission = await isLocationPermissionGranted();
      if (!hasPermission) {
        hasPermission = await requestLocationPermission();
        if (!hasPermission) return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      return position;
    } catch (e) {
      print('Error getting position: $e');
      return null;
    }
  }

  /// Check if user is within Bacoor, Cavite city
  static Future<Map<String, dynamic>> checkIfInBacoor() async {
    try {
      final position = await getCurrentPosition();
      
      if (position == null) {
        return {
          'isInBacoor': false,
          'hasLocation': false,
          'message': 'Could not obtain location. Please enable location services.',
          'city': null,
          'latitude': null,
          'longitude': null,
        };
      }

      final isInBounds = _isLocationInBacoor(position.latitude, position.longitude);
      
      // Get address for city confirmation
      String? detectedCity;
      try {
        final placemarks = await geo.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          detectedCity = placemarks.first.locality ?? placemarks.first.administrativeArea;
        }
      } catch (e) {
        print('Error getting placemark: $e');
      }

      final isDetectedBacoor = _matchesBacoorLocality(detectedCity);
      final isAllowed = isDetectedBacoor || isInBounds;

      return {
        'isInBacoor': isAllowed,
        'hasLocation': true,
        'message': isAllowed
            ? (isDetectedBacoor
                ? 'Location verified: Bacoor locality detected (${bacoorPsgc})'
                : 'Location verified: You are within Bacoor, Cavite bounds')
            : 'Location warning: You are outside Bacoor, Cavite',
        'city': detectedCity,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'withinBounds': isInBounds,
        'localityMatched': isDetectedBacoor,
        'psgc': bacoorPsgc,
      };
    } catch (e) {
      print('Error checking Bacoor location: $e');
      return {
        'isInBacoor': false,
        'hasLocation': false,
        'message': 'Error checking location: $e',
        'city': null,
        'latitude': null,
        'longitude': null,
      };
    }
  }

  /// Private helper to check coordinates against Bacoor bounds
  static bool _isLocationInBacoor(double latitude, double longitude) {
    return latitude >= bacoorMinLat &&
        latitude <= bacoorMaxLat &&
        longitude >= bacoorMinLon &&
        longitude <= bacoorMaxLon;
  }

  static bool _matchesBacoorLocality(String? locality) {
    final normalized = (locality ?? '').trim().toLowerCase();
    return normalized == 'bacoor' || normalized == 'bacoor city';
  }

  /// Get distance from Bacoor center (in km)
  static double getDistanceFromBacoorCenter(double latitude, double longitude) {
    const bacoorCenterLat = 14.43;
    const bacoorCenterLon = 120.96;

    return Geolocator.distanceBetween(
      latitude,
      longitude,
      bacoorCenterLat,
      bacoorCenterLon,
    ) / 1000; // Convert to km
  }
}
