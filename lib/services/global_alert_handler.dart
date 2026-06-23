import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../main.dart';

class GlobalAlertHandler {
  static final Map<String, DateTime> _lastModalTimeByCamera = {};
  static final Map<String, String> _lastModalTypeByCamera = {};
  static final Map<String, DateTime> _cautionSnoozeUntilByCamera = {};
  static const Duration modalCooldown = Duration(seconds: 30);
  static const Duration cautionSnoozeDuration = Duration(minutes: 5);
  static final ValueNotifier<bool> modalOpenListenable = ValueNotifier<bool>(false);
  static int _activeModalCount = 0;

  static final Map<String, int> _dangerCounterByCamera = {};
  static final Map<String, int> _confirmationCounterByCamera = {};
  static const int requiredStableCycles = 2;

  static final Map<String, bool> _dispatcherAlertSentByCamera = {};

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

  static Future<void> showFireModal({
    required double alert,
    required double severity,
    required String snapshotUrl,
    String snapshotBase64 = "",
    String deviceName = "Unknown Camera",
    String dominantSource = "unknown",
  }) async {
    print("🔥 FireModal | severity=$severity | alert=$alert");
    print("📍 Route now: ${currentRouteName.value}");

    final bool cautionNow =
        (severity >= 0.46 && alert >= 0.60) ||
        (severity >= 0.55 && alert >= 0.45);

    final bool confirmationNow =
        (severity >= 0.70 && alert >= 0.40) ||
        (severity >= 0.95 && alert >= 0.55);

    final bool dangerousNow =
        (severity >= 0.90 && alert >= 0.70);

    final bool singleSignalHighSpike =
        (severity >= 0.90 || alert >= 0.90) &&
        !(severity >= 0.90 && alert >= 0.90);

    final cameraId = deviceName.trim().isEmpty ? "Unknown Camera" : deviceName.trim();

    final currentDangerCounter = _dangerCounterByCamera[cameraId] ?? 0;
    final currentConfirmationCounter =
        _confirmationCounterByCamera[cameraId] ?? 0;

    if (dangerousNow) {
      _dangerCounterByCamera[cameraId] = currentDangerCounter + 1;
    } else {
      _dangerCounterByCamera[cameraId] = 0;
    }

    if (confirmationNow) {
      _confirmationCounterByCamera[cameraId] = currentConfirmationCounter + 1;
    } else {
      _confirmationCounterByCamera[cameraId] = 0;
    }

    final dangerCounter = _dangerCounterByCamera[cameraId] ?? 0;
    final confirmationCounter = _confirmationCounterByCamera[cameraId] ?? 0;

    final bool isDangerous = dangerCounter >= requiredStableCycles;

    final bool isConfirmation =
        (confirmationCounter >= requiredStableCycles || singleSignalHighSpike) &&
        !isDangerous;

    final bool isCaution =
        cautionNow && !isConfirmation && !isDangerous;

    print(
      "Counters[$cameraId] → danger=$dangerCounter confirmation=$confirmationCounter "
      "States → danger=$isDangerous confirmation=$isConfirmation caution=$isCaution "
      "singleSignalHighSpike=$singleSignalHighSpike",
    );

    if (!isDangerous && !isConfirmation && !isCaution) {
      if (_dispatcherAlertSentByCamera[cameraId] == true) {
        print("✅ Incident resolved for $cameraId, dispatcher lock reset");
      }
      _dispatcherAlertSentByCamera[cameraId] = false;
      return;
    }

    final String alertType = isDangerous
        ? "🔥 EXTREME FIRE DANGER"
        : isConfirmation
            ? "⚠️ CONFIRMATION REQUIRED: FIRE-LIKE ACTIVITY"
            : "⚠️ CAUTION: FIRE-LIKE ACTIVITY";

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final userProfile = await _getUserProfile();

    await _createUserAlert(
      alert,
      severity,
      snapshotUrl,
      snapshotBase64,
      deviceName,
      uid,
      alertType,
      dominantSource,
    );

    if (isDangerous) {
      if (!(_dispatcherAlertSentByCamera[cameraId] ?? false)) {
        await _createDispatcherAlert(
          userProfile,
          snapshotUrl,
          snapshotBase64,
          deviceName,
          alertType,
          dominantSource: dominantSource,
        );
        _dispatcherAlertSentByCamera[cameraId] = true;
      }

      _dangerCounterByCamera[cameraId] = 0;
      _confirmationCounterByCamera[cameraId] = 0;

      if (_shouldShowModalFor(cameraId, "dangerous")) {
        _showHighModal(
          snapshotUrl,
          snapshotBase64,
          alertType,
          deviceName,
          dominantSource,
        );
      }
      return;
    }

    if (singleSignalHighSpike) {
      print("⚠️ Single high spike detected, forcing confirmation modal");
      if (!hasActiveModal && _shouldShowModalFor(cameraId, "confirmation")) {
        _showMediumModal(
          userProfile,
          snapshotUrl,
          snapshotBase64,
          deviceName,
          "⚠️ CONFIRMATION REQUIRED: FIRE-LIKE ACTIVITY",
          dominantSource,
        );
      }
      return;
    }

    if (isConfirmation && _shouldShowModalFor(cameraId, "confirmation")) {
      _showMediumModal(
        userProfile,
        snapshotUrl,
        snapshotBase64,
        deviceName,
        alertType,
        dominantSource,
      );
      return;
    }

    if (isCaution && _shouldShowModalFor(cameraId, "caution")) {
      _showMediumModal(
        userProfile,
        snapshotUrl,
        snapshotBase64,
        deviceName,
        alertType,
        dominantSource,
      );
    }
  }

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
    String snapshotBase64,
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
      "snapshotBase64": snapshotBase64,
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
    String snapshotBase64,
    String deviceName,
    String alertType, {
    String? description,
    String dominantSource = "unknown",
  }) async {
    await FirebaseFirestore.instance.collection("alerts").add({
      "type": alertType,
      "location": deviceName,
      "description": description ?? "Fire detected in $deviceName",
      "snapshotUrl": snapshotUrl,
      "snapshotBase64": snapshotBase64,
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

  static bool _shouldShowModalFor(String cameraId, String type) {
    if (hasActiveModal) {
      return false;
    }

    if (type == "dangerous") {
      return true;
    }

    final cautionSnoozeUntil = _cautionSnoozeUntilByCamera[cameraId];
    if ((type == "caution" || type == "confirmation") &&
        cautionSnoozeUntil != null) {
      if (DateTime.now().isBefore(cautionSnoozeUntil)) {
        return false;
      }
    }

    final lastModalTime = _lastModalTimeByCamera[cameraId];
    final lastModalType = _lastModalTypeByCamera[cameraId];

    if (lastModalTime == null || lastModalType == null) {
      return true;
    }

    if (lastModalType != type) {
      return true;
    }

    return DateTime.now().difference(lastModalTime) > modalCooldown;
  }

  static void _recordModalShown(String cameraId, String type) {
    _lastModalTimeByCamera[cameraId] = DateTime.now();
    _lastModalTypeByCamera[cameraId] = type;
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

  static Uint8List? _decodeBase64Image(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (e) {
      print("⚠️ Failed to decode base64 image: $e");
      return null;
    }
  }

  static Widget _snapshotWidget({
    required String snapshotUrl,
    required String snapshotBase64,
  }) {
    final bytes = _decodeBase64Image(snapshotBase64);

    if (bytes != null) {
      return Image.memory(
        bytes,
        height: 160,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 160,
          child: Center(child: Text("Base64 snapshot unavailable")),
        ),
      );
    }

    if (snapshotUrl.startsWith("http")) {
      return Image.network(
        snapshotUrl,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 160,
          child: Center(child: Text("Snapshot unavailable")),
        ),
      );
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
    String snapshotBase64,
    String alertType,
    String cameraId,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(cameraId);

    _recordModalShown(cameraId, "dangerous");
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
              _snapshotWidget(
                snapshotUrl: snapshotUrl,
                snapshotBase64: snapshotBase64,
              ),
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
    String snapshotBase64,
    String deviceName,
    String alertType,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(deviceName);

    final modalType =
        alertType.contains("CONFIRMATION REQUIRED") ? "confirmation" : "caution";

    _recordModalShown(deviceName, modalType);
    _beginModal();

    const Duration inactivityTimeout = Duration(seconds: 15);
    bool resolved = false;
    int remainingSeconds = inactivityTimeout.inSeconds;
    bool timerStarted = false;
    Timer? countdownTimer;
    bool suppressForFiveMinutes = false;
    int snoozePreviewSeconds = cautionSnoozeDuration.inSeconds;

    void stopCountdown() {
      countdownTimer?.cancel();
      countdownTimer = null;
    }

    Future.delayed(inactivityTimeout, () async {
      if (resolved || (_dispatcherAlertSentByCamera[deviceName] ?? false)) return;
      resolved = true;
      stopCountdown();

      if (suppressForFiveMinutes && snoozePreviewSeconds > 0) {
        _cautionSnoozeUntilByCamera[deviceName] =
            DateTime.now().add(Duration(seconds: snoozePreviewSeconds));
      }

      final delayCtx = navigatorKey.currentState?.overlay?.context;
      if (delayCtx != null && Navigator.canPop(delayCtx)) {
        Navigator.pop(delayCtx);
      }

      await _createDispatcherAlert(
        user,
        snapshotUrl,
        snapshotBase64,
        deviceName,
        "🔥 FIRE ALERT (NO USER RESPONSE)",
        description: "Fire detected in $deviceName, user no response",
        dominantSource: dominantSource,
      );

      _dispatcherAlertSentByCamera[deviceName] = true;

      Future.delayed(const Duration(milliseconds: 150), () {
        _showAutoDispatchModal(
          snapshotUrl,
          snapshotBase64,
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
                if (suppressForFiveMinutes && snoozePreviewSeconds > 0) {
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
                  _snapshotWidget(
                    snapshotUrl: snapshotUrl,
                    snapshotBase64: snapshotBase64,
                  ),
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
                    value: suppressForFiveMinutes,
                    onChanged: (value) {
                      suppressForFiveMinutes = value ?? false;
                      if (!suppressForFiveMinutes) {
                        snoozePreviewSeconds = cautionSnoozeDuration.inSeconds;
                      }
                      setState(() {});
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (suppressForFiveMinutes)
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
                  if (suppressForFiveMinutes) {
                    _cautionSnoozeUntilByCamera[deviceName] =
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
                  if (suppressForFiveMinutes) {
                    _cautionSnoozeUntilByCamera[deviceName] =
                        DateTime.now().add(Duration(seconds: snoozePreviewSeconds));
                  }
                  Navigator.pop(dialogCtx);

                  if (_dispatcherAlertSentByCamera[deviceName] == true) {
                    print("🚫 Dispatcher already alerted, skipping duplicate");
                    return;
                  }

                  await _createDispatcherAlert(
                    user,
                    snapshotUrl,
                    snapshotBase64,
                    deviceName,
                    "🔥 FIRE CONFIRMED BY USER",
                    dominantSource: dominantSource,
                  );

                  _dispatcherAlertSentByCamera[deviceName] = true;
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
    String snapshotBase64,
    String message,
    String cameraId,
    String dominantSource,
  ) {
    final ctx = _dialogContext();
    if (ctx == null) return;
    final thermalUrlFuture = _fetchThermalSnapshotUrl(cameraId);

    _recordModalShown(cameraId, "auto");
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
              _snapshotWidget(
                snapshotUrl: snapshotUrl,
                snapshotBase64: snapshotBase64,
              ),
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