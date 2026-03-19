import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'background_ai_task.dart';
import 'foreground_ai_service.dart';

class BackgroundAIManager {
  static const String periodicTaskName = "periodicAITask";
  static const String foregroundTaskName = "foregroundAIService";

  static Future<bool> hasLinkedCameras() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final byUid = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (byUid.exists) {
      final data = byUid.data() ?? <String, dynamic>{};
      final cameraIds = data['cameraIds'];
      if (cameraIds is List && cameraIds.isNotEmpty) return true;
    }

    final byEmail = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (byEmail.docs.isEmpty) return false;

    final data = byEmail.docs.first.data();
    final cameraIds = data['cameraIds'];
    return cameraIds is List && cameraIds.isNotEmpty;
  }

  /// Initialize WorkManager (call once at app startup)
  static Future<void> initWorkManager() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true, // Set to false in production
    );
  }

  /// Start periodic background task (every 15 minutes)
  /// Works even when app is closed
  static Future<bool> startPeriodicTask({
    Duration frequency = const Duration(minutes: 15),
  }) async {
    if (!await hasLinkedCameras()) {
      print('⚠️ Skipping periodic AI task: no linked cameras for current user.');
      return false;
    }

    await Workmanager().registerPeriodicTask(
      periodicTaskName,
      periodicTaskName,
      frequency: frequency,
      constraints: Constraints(
        networkType: NetworkType.connected, // Requires internet
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: Duration(minutes: 5),
    );
    print('✅ Periodic AI task registered (every ${frequency.inMinutes} min)');
    return true;
  }

  /// Stop periodic background task
  static Future<void> stopPeriodicTask() async {
    await Workmanager().cancelByUniqueName(periodicTaskName);
    print('🛑 Periodic AI task cancelled');
  }

  /// Initialize Foreground Task
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'apula_ai_service',
        channelName: 'APULA AI Monitoring',
        channelDescription: 'Continuous fire detection AI monitoring',
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Start foreground service (continuous monitoring)
  /// Shows persistent notification, runs continuously
  static Future<bool> startForegroundService() async {
    if (!await hasLinkedCameras()) {
      print('⚠️ Skipping foreground AI service: no linked cameras for current user.');
      return false;
    }

    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    // Request permissions
    if (!await FlutterForegroundTask.canDrawOverlays) {
      await FlutterForegroundTask.openSystemAlertWindowSettings();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    // Start service
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'APULA AI Monitoring',
        notificationText: 'Initializing fire detection AI...',
        callback: startCallback,
      );
      print('✅ Foreground AI service started');
      return true;
    } catch (e) {
      print('❌ Error starting foreground service: $e');
      return false;
    }
  }

  /// Stop foreground service
  static Future<bool> stopForegroundService() async {
    try {
      await FlutterForegroundTask.stopService();
      print('🛑 Foreground AI service stopped');
      return true;
    } catch (e) {
      print('❌ Error stopping foreground service: $e');
      return false;
    }
  }

  /// Check if foreground service is running
  static Future<bool> isForegroundServiceRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

// Callback to start foreground task handler
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ForegroundAITaskHandler());
}
