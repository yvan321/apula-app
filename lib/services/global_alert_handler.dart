import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../main.dart';

class GlobalAlertHandler {
  static DateTime? _lastModalTime;
  static String? _lastModalType;
  static DateTime? _cautionSnoozeUntil;
  static const Duration modalCooldown = Duration(seconds: 30);
  static const Duration cautionSnoozeDuration = Duration(minutes: 5);
  static final ValueNotifier<bool> modalOpenListenable = ValueNotifier<bool>(false);
  static int _activeModalCount = 0;

  // Stability counters
  static int _dangerCounter = 0;
  static int _ignitionCounter = 0;
  static const int requiredStableCycles = 2;

  // ✅ SINGLE DISPATCH GUARD (FIX)
  static bool _dispatcherAlertSent = false;

  static bool get hasActiveModal => modalOpenListenable.value;

  static String _sourceLabel(String source) {
    final normalized = source.toLowerCase();
    if (normalized == "cctv") return "CCTV / Vision";
    if (normalized == "sensor") return "Sensor / IoT";
    if (normalized == "mixed") return "Mixed (both)";
    return "Unknown";
  }

  static Color _dialogActionColor(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return isDarkMode ? Colors.white : const Color(0xFFA30000);
  }

  // =======================================================
  // MAIN ENTRY POINT
  // =======================================================
  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String deviceName = "Unknown Camera",
    String dominantSource = "unknown",
  }) async {
    print("🔥 FireModal | severity=$severity | alert=$alert");

    // ===================================================
    // CNN DECISION LOGIC
    // ===================================================
    final bool cautionNow =
        severity >= 0.40 && alert >= 0.73;

    final bool ignitionNow =
        severity >= 0.55 && alert >= 0.75;

    final bool dangerousNow =
        severity >= 0.70 && alert >= 0.80;

    final bool strongSpike =
      severity >= 0.90 && alert >= 0.90;

    final bool urgentHighAlert =
      severity >= 0.70 && alert >= 0.95;

    // ===================================================
    // STABILITY LOGIC
    // ===================================================
    if (dangerousNow) {
      _dangerCounter++;
    } else {
      _dangerCounter = 0;
    }

    if (ignitionNow) {
      _ignitionCounter++;
    } else {
      _ignitionCounter = 0;
    }

    final bool isDangerous =
      urgentHighAlert || strongSpike || _dangerCounter >= requiredStableCycles;

    final bool isIgnition =
        _ignitionCounter >= requiredStableCycles && !isDangerous;

    final bool isCaution =
        cautionNow && !isDangerous && !isIgnition;

    print(
      "Counters → danger=$_dangerCounter ignition=$_ignitionCounter "
      "States → danger=$isDangerous ignition=$isIgnition caution=$isCaution"
    );

    // ===================================================
    // RESET INCIDENT WHEN NORMAL
    // ===================================================
    if (!isDangerous && !isIgnition && !isCaution) {
      if (_dispatcherAlertSent) {
        print("✅ Incident resolved, dispatcher lock reset");
      }
      _dispatcherAlertSent = false;
      return;
    }

    // ===================================================
    // ALERT TYPE
    // ===================================================
    final String alertType = isDangerous
        ? "🔥 EXTREME FIRE DANGER"
        : isIgnition
            ? "🔥 IGNITION ANOMALY DETECTED"
            : "⚠️ CAUTION: FIRE-LIKE ACTIVITY";

    // ===================================================
    // USER CONTEXT
    // ===================================================
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userProfile = await _getUserProfile();

    // ===================================================
    // ALWAYS LOG USER ALERT
    // ===================================================
    await _createUserAlert(
      alert,
      severity,
      snapshotUrl,
      deviceName,
      uid,
      alertType,
      dominantSource,
    );

    // ===================================================
    // 🔴 AUTOMATIC DISPATCHER ALERT (DANGEROUS ONLY)
    // ===================================================
    if (isDangerous && !_dispatcherAlertSent) {
      await _createDispatcherAlert(
        userProfile,
        snapshotUrl,
        deviceName,
        alertType,
        dominantSource: dominantSource,
      );

      _dispatcherAlertSent = true;
      _dangerCounter = 0;
      _ignitionCounter = 0;

      if (_shouldShowModalFor("dangerous")) {
        _showHighModal(snapshotUrl, alertType, deviceName, dominantSource);
      }
      return;
    }

    // ===================================================
    // 🟡 CAUTION MODE (USER CONFIRMATION)
    // ===================================================
    if (isCaution && _shouldShowModalFor("caution")) {
      _showMediumModal(
        userProfile,
        snapshotUrl,
        deviceName,
        alertType,
        dominantSource,
      );
    }
  }

  // =======================================================
  // FIRESTORE HELPERS
  // =======================================================
  static Future<Map<String, dynamic>?> _getUserProfile() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: email)
        .limit(1)
        .get();

    return snap.docs.isEmpty ? null : snap.docs.first.data();
  }

  static Future<void> _createUserAlert(
    double alert,
    double severity,
    String snapshotUrl,
    String deviceName,
    String? uid,
    String type,
    String dominantSource,
  ) async {
    await FirebaseFirestore.instance.collection("user_alerts").add({
      "alert": alert,
      "severity": severity,
      "type": type,
      "snapshotUrl": snapshotUrl,
      "device": deviceName,
      "deviceName": deviceName,
      "dominantSource": dominantSource,
      "source": dominantSource,
      "sourceLabel": _sourceLabel(dominantSource),
      "timestamp": FieldValue.serverTimestamp(),
      "read": false,
      "userId": uid,
      "userEmail": FirebaseAuth.instance.currentUser?.email,
    });
  }

  static Future<void> _createDispatcherAlert(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
    String alertType,
    {String? description, String dominantSource = "unknown"}
  ) async {
    await FirebaseFirestore.instance.collection("alerts").add({
      "type": alertType,
      "location": deviceName,
      "description": description ?? "Fire detected in $deviceName",
      "snapshotUrl": snapshotUrl,
      "dominantSource": dominantSource,
      "source": dominantSource,
      "sourceLabel": _sourceLabel(dominantSource),
      "status": "Pending",
      "timestamp": FieldValue.serverTimestamp(),
      "read": false,
      "userName": user?["name"] ?? "Unknown",
      "userAddress": user?["address"] ?? "N/A",
      "userContact": user?["contact"] ?? "N/A",
      "userEmail": user?["email"] ?? "N/A",
      "userLatitude": user?["latitude"] ?? 0,
      "userLongitude": user?["longitude"] ?? 0,
    });
  }

  // =======================================================
  // MODAL HELPERS
  // =======================================================
  static bool _shouldShowModalFor(String type) {
    if (hasActiveModal) {
      return false;
    }
    if (type == "dangerous") {
      return true;
    }
    if (type == "caution" && _cautionSnoozeUntil != null) {
      if (DateTime.now().isBefore(_cautionSnoozeUntil!)) {
        return false;
      }
    }
    if (_lastModalTime == null || _lastModalType == null) {
      return true;
    }
    if (_lastModalType != type) {
      return true;
    }
    return DateTime.now().difference(_lastModalTime!) > modalCooldown;
  }

  static void _recordModalShown(String type) {
    _lastModalTime = DateTime.now();
    _lastModalType = type;
  }

  static void _beginModal() {
    _activeModalCount += 1;
    if (!modalOpenListenable.value) {
      modalOpenListenable.value = true;
    }
  }

  static void _endModal() {
    if (_activeModalCount > 0) {
      _activeModalCount -= 1;
    }
    if (_activeModalCount == 0 && modalOpenListenable.value) {
      modalOpenListenable.value = false;
    }
  }

  static BuildContext? _dialogContext() {
    return navigatorKey.currentState?.overlay?.context ??
        navigatorKey.currentState?.context ??
        navigatorKey.currentContext;
  }

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  static Widget _snapshotWidget(String url) {
    if (url.startsWith("http")) {
      return Image.network(url, height: 160, fit: BoxFit.cover);
    }
    return const SizedBox(
      height: 160,
      child: Center(child: Text("No snapshot available")),
    );
  }

  static Future<String> _fetchThermalSnapshotUrl(String cameraId) async {
    try {
      final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);
      final trimmedCameraId = cameraId.trim();
      final digitMatch = RegExp(r"\d+").firstMatch(trimmedCameraId);
      final cameraDigits = digitMatch?.group(0);

      final Set<String> nodeCandidates = {
        if (trimmedCameraId.isNotEmpty) "thermal_cam_$trimmedCameraId",
        if (trimmedCameraId.startsWith("cam_"))
          "thermal_cam_${trimmedCameraId.substring(4)}",
        if (cameraDigits != null) "thermal_cam_$cameraDigits",
        if (cameraDigits != null) "thermal_cam_${cameraDigits.padLeft(2, '0')}",
      };

      for (final node in nodeCandidates) {
        for (final key in const ["image_url", "image_path"]) {
          final snap = await rtdb.ref("$node/latest/$key").get();
          final rawPath = snap.value?.toString().trim() ?? "";
          if (rawPath.isEmpty) continue;

          if (rawPath.startsWith("http://") || rawPath.startsWith("https://")) {
            return rawPath;
          }

          final normalizedPath =
              rawPath.startsWith("/") ? rawPath.substring(1) : rawPath;

          return FirebaseStorage.instanceFor(app: yoloFirebaseApp)
              .ref(normalizedPath)
              .getDownloadURL();
        }
      }

      return "";
    } catch (e) {
      print("⚠️ Failed to load thermal snapshot for $cameraId: $e");
      return "";
    }
  }

  static Widget _thermalSnapshotWidget(Future<String> thermalUrlFuture) {
    return FutureBuilder<String>(
      future: thermalUrlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final url = snapshot.data ?? "";
        if (url.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Thermal Snapshot",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              Image.network(
                url,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 40,
                  child: Center(child: Text("Thermal snapshot unavailable")),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showHighModal(
    String snapshotUrl,
    String alertType,
    String cameraId,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(cameraId);

    _recordModalShown("dangerous");
    _beginModal();

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(alertType),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _snapshotWidget(snapshotUrl),
              _thermalSnapshotWidget(thermalUrlFuture),
              const SizedBox(height: 12),
              Text("Likely Trigger: ${_sourceLabel(dominantSource)}"),
              const SizedBox(height: 8),
              const Text(
                "Emergency responders have been notified automatically.",
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _dialogActionColor(ctx),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    ).whenComplete(_endModal);
  }

  static void _showMediumModal(
    Map<String, dynamic>? user,
    String snapshotUrl,
    String deviceName,
    String alertType,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(deviceName);

    _recordModalShown("caution");
    _beginModal();

    const Duration inactivityTimeout = Duration(seconds: 15);
    bool resolved = false;
    int remainingSeconds = inactivityTimeout.inSeconds;
    bool timerStarted = false;
    Timer? countdownTimer;
    bool suppressForThirtyMinutes = false;
    int snoozePreviewSeconds = cautionSnoozeDuration.inSeconds;

    void stopCountdown() {
      countdownTimer?.cancel();
      countdownTimer = null;
    }

    Future.delayed(inactivityTimeout, () async {
      if (resolved || _dispatcherAlertSent) return;
      resolved = true;
      stopCountdown();

      if (suppressForThirtyMinutes && snoozePreviewSeconds > 0) {
        _cautionSnoozeUntil =
            DateTime.now().add(Duration(seconds: snoozePreviewSeconds));
      }

      final delayCtx = navigatorKey.currentState?.overlay?.context;
      if (delayCtx != null && Navigator.canPop(delayCtx)) {
        Navigator.pop(delayCtx);
      }

      await _createDispatcherAlert(
        user,
        snapshotUrl,
        deviceName,
        "🔥 FIRE ALERT (NO USER RESPONSE)",
        description: "Fire detected in $deviceName, user no response",
        dominantSource: dominantSource,
      );

      _dispatcherAlertSent = true;

      Future.delayed(const Duration(milliseconds: 150), () {
        _showAutoDispatchModal(
          snapshotUrl,
          "Alert sent due to user no response.",
          deviceName,
          dominantSource,
        );
      });
    });

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setState) {
          if (!timerStarted) {
            timerStarted = true;
            countdownTimer = Timer.periodic(
              const Duration(seconds: 1),
              (_) {
                if (resolved) {
                  stopCountdown();
                  return;
                }
                if (remainingSeconds <= 0) {
                  stopCountdown();
                  return;
                }
                remainingSeconds -= 1;
                if (suppressForThirtyMinutes && snoozePreviewSeconds > 0) {
                  snoozePreviewSeconds -= 1;
                }
                setState(() {});
              },
            );
          }

          return AlertDialog(
            title: Text(alertType),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _snapshotWidget(snapshotUrl),
                  _thermalSnapshotWidget(thermalUrlFuture),
                  const SizedBox(height: 12),
                  const Text("Please confirm if this is a real fire."),
                  const SizedBox(height: 6),
                  Text(
                    "Likely Trigger: ${_sourceLabel(dominantSource)}",
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Auto-sending in ${remainingSeconds}s if no response.",
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Don't remind me again for 5 minutes"),
                    value: suppressForThirtyMinutes,
                    onChanged: (value) {
                      suppressForThirtyMinutes = value ?? false;
                      if (!suppressForThirtyMinutes) {
                        snoozePreviewSeconds = cautionSnoozeDuration.inSeconds;
                      }
                      setState(() {});
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (suppressForThirtyMinutes)
                    Text(
                      "Snooze: ${_formatDuration(Duration(seconds: snoozePreviewSeconds))}",
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: _dialogActionColor(dialogCtx),
                ),
                onPressed: () {
                  resolved = true;
                  stopCountdown();
                  if (suppressForThirtyMinutes) {
                    _cautionSnoozeUntil =
                        DateTime.now().add(Duration(seconds: snoozePreviewSeconds));
                  }
                  Navigator.pop(dialogCtx);
                },
                child: const Text("FALSE ALARM"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA30000),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  resolved = true;
                  stopCountdown();
                  if (suppressForThirtyMinutes) {
                    _cautionSnoozeUntil =
                    DateTime.now().add(Duration(seconds: snoozePreviewSeconds));
                  }
                  Navigator.pop(dialogCtx);

                  if (_dispatcherAlertSent) {
                    print("🚫 Dispatcher already alerted, skipping duplicate");
                    return;
                  }

                  await _createDispatcherAlert(
                    user,
                    snapshotUrl,
                    deviceName,
                    "🔥 FIRE CONFIRMED BY USER",
                    dominantSource: dominantSource,
                  );

                  _dispatcherAlertSent = true;
                },
                child: const Text("CONFIRM FIRE"),
              ),
            ],
          );
        },
      ),
    ).whenComplete(_endModal);
  }

  static void _showAutoDispatchModal(
    String snapshotUrl,
    String message,
    String cameraId,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(cameraId);

    _recordModalShown("auto");
    _beginModal();

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("ALERT SENT"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _snapshotWidget(snapshotUrl),
              _thermalSnapshotWidget(thermalUrlFuture),
              const SizedBox(height: 12),
              Text("Likely Trigger: ${_sourceLabel(dominantSource)}"),
              const SizedBox(height: 8),
              Text(message),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _dialogActionColor(ctx),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    ).whenComplete(_endModal);
  }
}
