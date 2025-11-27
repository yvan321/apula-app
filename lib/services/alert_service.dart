// lib/services/alert_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class AlertService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String userAlertsCollection = 'user_alerts';
  static const String dispatcherCollection = 'alerts';

  /// USER ALERT (medium or high severity)
  static Future<void> sendUserAlert({
    required String deviceName,
    required String snapshotUrl,
    required double alert,
    required double severity,
  }) async {
    try {
      await _db.collection(userAlertsCollection).add({
        'type': severity >= 0.6 ? 'Severe Fire Risk' : 'Possible Fire',
        'deviceName': deviceName,
        'snapshotUrl': snapshotUrl,
        'alert': alert,
        'severity': severity,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      print("AlertService: sendUserAlert — success");
    } catch (e, st) {
      print("AlertService: sendUserAlert ERROR: $e\n$st");
    }
  }

  /// DISPATCHER ALERT (only after CONFIRM FIRE)
  static Future<void> sendDispatcherAlert({
    required String deviceName,
    required String description,
    required Map<String, dynamic> user,
    required String snapshotUrl,
  }) async {
    try {
      await _db.collection(dispatcherCollection).add({
        'type': '🔥 Fire Detected',
        'location': deviceName,
        'description': description,
        'snapshotUrl': snapshotUrl,
        'status': 'Pending',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,

        // User metadata
        'userName': user['name'],
        'userAddress': user['address'],
        'userContact': user['contact'],
        'userEmail': user['email'],
        'userLatitude': user['latitude'],
        'userLongitude': user['longitude'],
      });

      print("AlertService: sendDispatcherAlert — success");
    } catch (e, st) {
      print("AlertService: sendDispatcherAlert ERROR: $e\n$st");
    }
  }
}
