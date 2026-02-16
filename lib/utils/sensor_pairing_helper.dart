import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../main.dart';

/// Helper class to manage sensor-camera pairing
class SensorPairingHelper {
  static DatabaseReference get _sensorRef =>
      FirebaseDatabase.instanceFor(app: yoloFirebaseApp).ref('sensor_data/latest');

  /// Get sensor data for a specific camera, with smart fallback
  /// 
  /// Priority:
  /// 1. Look for sensor with sensor_id matching cameraId
  /// 2. If not found, return first available sensor (shared)
  /// 3. If no sensors, return null
  static Future<Map<String, dynamic>?> getSensorForCamera(String cameraId) async {
    try {
      final snapshot = await _sensorRef.get();
      
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
      
      // Case 2: Multiple sensors (if structure changes later)
      // This allows for future expansion where you might have:
      // sensor_data/latest/cam_01/{data}, sensor_data/latest/cam_02/{data}
      
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
    return _sensorRef.onValue.listen((event) {
      if (event.snapshot.value == null) {
        onData(null);
        return;
      }

      final data = event.snapshot.value;
      if (data is Map) {
        final sensorMap = Map<String, dynamic>.from(data);
        final sensorId = sensorMap['sensor_id']?.toString() ?? '';
        
        // Check if this sensor matches the camera or use as fallback
        if (sensorId == cameraId || sensorId.isNotEmpty) {
          onData(sensorMap);
          return;
        }
      }
      
      onData(null);
    });
  }

  /// Get all available sensors
  static Future<List<Map<String, dynamic>>> getAllSensors() async {
    try {
      final snapshot = await _sensorRef.get();
      
      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final data = snapshot.value;
      if (data is Map) {
        return [Map<String, dynamic>.from(data)];
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
