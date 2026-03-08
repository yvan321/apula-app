import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';

/// Helper class to manage sensor-camera pairing
class SensorPairingHelper {
  static DatabaseReference _sensorRefForCamera(String cameraId) =>
      FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
          .ref('sensor_data/$cameraId/latest');

  static DatabaseReference get _sensorRootRef =>
      FirebaseDatabase.instanceFor(app: yoloFirebaseApp).ref('sensor_data');

  /// Get sensor data for a specific camera, with smart fallback
  /// 
  /// Priority:
  /// 1. Look for sensor with sensor_id matching cameraId
  /// 2. If not found, return first available sensor (shared)
  /// 3. If no sensors, return null
  static Future<Map<String, dynamic>?> getSensorForCamera(String cameraId) async {
    try {
      var snapshot = await _sensorRefForCamera(cameraId).get();
      if (!snapshot.exists || snapshot.value == null) {
        snapshot = await FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
            .ref('sensor_data/latest')
            .get();
      }
      
      if (!snapshot.exists || snapshot.value == null) {
        return null;
      }

      final data = snapshot.value;
      
      // Case 1: Single sensor object with sensor_id field
      if (data is Map) {
        final sensorMap = Map<String, dynamic>.from(data);
        final sensorId = sensorMap['sensor_id']?.toString() ?? '';
        
        // Direct match
        if (sensorId == cameraId) {
          return sensorMap;
        }
        
        // Fallback to this sensor (shared)
        return sensorMap;
      }
      
      // Case 2: Unexpected structure
      
      return null;
    } catch (e) {
      print('❌ Error getting sensor for $cameraId: $e');
      return null;
    }
  }

  /// Listen to sensor changes for a specific camera
  static StreamSubscription<DatabaseEvent> listenToSensorForCamera(
    String cameraId,
    Function(Map<String, dynamic>?) onData,
  ) {
    return _sensorRefForCamera(cameraId).onValue.listen((event) {
      if (event.snapshot.value == null) {
        // Legacy fallback for older schema
        FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
            .ref('sensor_data/latest')
            .get()
            .then((fallbackSnap) {
          if (!fallbackSnap.exists || fallbackSnap.value == null) {
            onData(null);
            return;
          }

          final fallback = fallbackSnap.value;
          if (fallback is Map) {
            onData(Map<String, dynamic>.from(fallback));
            return;
          }

          onData(null);
        });
        return;
      }

      final data = event.snapshot.value;
      if (data is Map) {
        onData(Map<String, dynamic>.from(data));
        return;
      }
      
      onData(null);
    });
  }

  /// Get all available sensors
  static Future<List<Map<String, dynamic>>> getAllSensors() async {
    try {
      final snapshot = await _sensorRootRef.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final data = snapshot.value;
      if (data is Map) {
        final sensors = <Map<String, dynamic>>[];

        for (final entry in data.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          if (value is Map && value['latest'] is Map) {
            sensors.add(Map<String, dynamic>.from(value['latest'] as Map)
              ..putIfAbsent('camera_id', () => key));
          } else if (key == 'latest' && value is Map) {
            sensors.add(Map<String, dynamic>.from(value));
          }
        }

        return sensors;
      }
      
      return [];
    } catch (e) {
      print('❌ Error getting all sensors: $e');
      return [];
    }
  }

  /// Check if a camera has a paired sensor
  static Future<bool> hasSensor(String cameraId) async {
    final sensor = await getSensorForCamera(cameraId);
    return sensor != null;
  }

  /// Get sensor status message for display
  static Future<String> getSensorStatus(String cameraId) async {
    final sensor = await getSensorForCamera(cameraId);
    
    if (sensor == null) {
      return 'No sensor connected';
    }
    
    final sensorId = sensor['sensor_id']?.toString() ?? '';
    
    if (sensorId == cameraId) {
      return 'Paired sensor: $sensorId';
    }
    
    return 'Using shared sensor${sensorId.isNotEmpty ? ": $sensorId" : ""}';
  }
}
