import 'package:cloud_firestore/cloud_firestore.dart';

class AlertService {
  static final _alerts = FirebaseFirestore.instance.collection("alerts");

  // 🔔 Send alert to USER only (warning level)
  static Future<void> sendUserAlert({required String deviceName}) async {
    await _alerts.add({
      "type": "⚠️ Fire Warning",
      "device": deviceName,
      "target": "user",
      "timestamp": FieldValue.serverTimestamp(),
      "status": "Pending",
      "description": "CNN detected a moderate fire-risk from $deviceName."
    });
  }

  // 🚒 Send alert to DISPATCHER + user (emergency level)
  static Future<void> sendDispatcherAlert({required String deviceName}) async {
    await _alerts.add({
      "type": "🚨 Critical Fire Alert",
      "device": deviceName,
      "target": "dispatcher",
      "timestamp": FieldValue.serverTimestamp(),
      "status": "Urgent",
      "description": "CNN detected a SEVERE fire-risk from $deviceName."
    });
  }
}
