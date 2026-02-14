// USAGE EXAMPLES FOR BACKGROUND AI SERVICES

import 'package:flutter/material.dart';
import 'services/background_ai_manager.dart';
import 'widgets/background_service_control.dart';

/* ============================================
   OPTION 1: Using the UI Widget
   ============================================ */

// Add this to your settings screen or main menu:
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BackgroundServiceControl(),
              ),
            );
          },
          child: Text('Background AI Settings'),
        ),
      ),
    );
  }
}

/* ============================================
   OPTION 2: Programmatic Control
   ============================================ */

// Start continuous monitoring (foreground service)
void startContinuousMonitoring() async {
  final started = await BackgroundAIManager.startForegroundService();
  if (started) {
    print('✅ AI is now running continuously in background');
    // Shows persistent notification
    // Runs inference every 5 seconds
    // Works even when app is closed
  }
}

// Stop continuous monitoring
void stopContinuousMonitoring() async {
  await BackgroundAIManager.stopForegroundService();
  print('🛑 Continuous monitoring stopped');
}

// Enable periodic checks (every 15 minutes)
void enablePeriodicChecks() async {
  await BackgroundAIManager.startPeriodicTask(
    frequency: Duration(minutes: 15), // Can adjust frequency
  );
  print('✅ Periodic AI checks enabled');
  // Battery efficient
  // Works even when app is killed
  // No persistent notification
}

// Disable periodic checks
void disablePeriodicChecks() async {
  await BackgroundAIManager.stopPeriodicTask();
  print('🛑 Periodic checks disabled');
}

// Check if foreground service is running
void checkServiceStatus() async {
  final isRunning = await BackgroundAIManager.isForegroundServiceRunning();
  print('Foreground service running: $isRunning');
}

/* ============================================
   OPTION 3: Auto-start on App Launch
   ============================================ */

// In your main.dart, after initialization:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... Firebase initialization ...
  
  await BackgroundAIManager.initWorkManager();
  BackgroundAIManager.initForegroundTask();
  
  // Auto-start services (optional)
  await BackgroundAIManager.startPeriodicTask(); // Start periodic checks
  // OR
  // await BackgroundAIManager.startForegroundService(); // Start continuous monitoring
  
  runApp(MyApp());
}

/* ============================================
   COMPARISON: Which Service to Use?
   ============================================ */

/*
┌─────────────────────┬────────────────────┬─────────────────────┐
│ Feature             │ Foreground Service │ Periodic Task       │
├─────────────────────┼────────────────────┼─────────────────────┤
│ Update Frequency    │ Every 5 seconds    │ Every 15-60 minutes │
│ Battery Impact      │ High               │ Low                 │
│ Persistent Notif    │ Yes (required)     │ No                  │
│ Works when closed   │ Yes                │ Yes                 │
│ Works when killed   │ Yes                │ Yes                 │
│ Real-time detection │ Yes                │ No                  │
│ Best for            │ Critical alerts    │ Monitoring only     │
└─────────────────────┴────────────────────┴─────────────────────┘
*/

/* ============================================
   RESULTS LOCATION (Firebase)
   ============================================ */

/*
Foreground Service writes to:
  firebase.database().ref("cnn_results/foreground")
  
Periodic Task writes to:
  firebase.database().ref("cnn_results/background")

Both contain:
  {
    "fire_probability": 0.85,
    "no_fire_probability": 0.15,
    "prediction": "FIRE",
    "timestamp": "2026-02-13T10:30:00.000",
    "source": "foreground_service" or "background_task"
  }
*/

/* ============================================
   IMPORTANT NOTES
   ============================================ */

/*
✅ ANDROID:
   - Both services work fully
   - User must grant battery optimization exemption
   - Foreground service requires notification channel
   - WorkManager survives app restarts

⚠️ iOS:
   - Foreground service has LIMITED background time (iOS restrictions)
   - Periodic task uses Background Fetch (not guaranteed timing)
   - Apple decides when background tasks run
   - Consider using Push Notifications for iOS instead

🔋 BATTERY:
   - Foreground service drains battery faster
   - Use periodic task for better battery life
   - User can disable battery optimization

📍 PERMISSIONS:
   - Auto-requested on first use
   - User can deny and services won't work
   - Check permission status in settings
*/
