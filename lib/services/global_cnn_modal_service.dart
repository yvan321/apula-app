import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'cnn_listener_service.dart';
import 'global_alert_handler.dart';

class GlobalCnnModalService {
  static bool _initialized = false;
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _userSub;
  static Set<String> _activeCameraIds = <String>{};

  static final CnnCallback _modalCallback = (
    cameraId,
    alert,
    severity,
    snapshotUrl,
    dominantSource,
  ) {
    GlobalAlertHandler.showFireModal(
      alert: alert,
      severity: severity,
      snapshotUrl: snapshotUrl,
      deviceName: cameraId,
      dominantSource: dominantSource,
    );
  };

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Attach immediately for restored sessions so listeners are active
    // even before auth state stream emits again.
    _bindForUser(FirebaseAuth.instance.currentUser);

    _authSub = FirebaseAuth.instance.authStateChanges().listen(_bindForUser);
  }

  static void _bindForUser(User? user) {
    if (user == null) {
      _detachFromAllCameras();
      _userSub?.cancel();
      _userSub = null;
      return;
    }

    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      final nextCameraIds = _extractCameraIds(snapshot);
      _syncCameraListeners(nextCameraIds);
    });
  }

  static Set<String> _extractCameraIds(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (snapshot.docs.isEmpty) return <String>{};

    final data = snapshot.docs.first.data();
    final rawCameraIds = data['cameraIds'];
    if (rawCameraIds is! List) return <String>{};

    final ids = rawCameraIds
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    return ids;
  }

  static void _syncCameraListeners(Set<String> nextCameraIds) {
    final toAdd = nextCameraIds.difference(_activeCameraIds).toList();
    final toRemove = _activeCameraIds.difference(nextCameraIds).toList();

    if (toAdd.isNotEmpty) {
      CnnListenerService.startListening(toAdd, _modalCallback);
    }

    if (toRemove.isNotEmpty) {
      CnnListenerService.removeCallbacks(toRemove, _modalCallback);
    }

    _activeCameraIds = nextCameraIds;
  }

  static void _detachFromAllCameras() {
    if (_activeCameraIds.isEmpty) return;

    CnnListenerService.removeCallbacks(_activeCameraIds.toList(), _modalCallback);
    _activeCameraIds = <String>{};
  }

  static Future<void> dispose() async {
    _detachFromAllCameras();
    await _userSub?.cancel();
    await _authSub?.cancel();
    _userSub = null;
    _authSub = null;
    _initialized = false;
  }
}
