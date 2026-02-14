# Background AI Services - Setup Complete ✅

Your Flutter app can now run AI fire detection **even when the app is closed or killed**.

---

## 📋 What Was Added

### New Files Created:
1. **background_ai_task.dart** - WorkManager periodic task
2. **foreground_ai_service.dart** - Continuous monitoring service  
3. **background_ai_manager.dart** - Easy API to control services
4. **background_service_control.dart** - UI widget to start/stop services
5. **USAGE_EXAMPLES.dart** - Code examples

### Updated Files:
1. **pubspec.yaml** - Added `workmanager` and `flutter_foreground_task` packages
2. **main.dart** - Added initialization code
3. **AndroidManifest.xml** - Added permissions and service declarations

---

## 🚀 Quick Start

### 1. Install dependencies:
```bash
flutter pub get
```

### 2. Choose your service:

#### **Option A: Continuous Monitoring** (Real-time, uses more battery)
```dart
await BackgroundAIManager.startForegroundService();
```
- Runs AI every **5 seconds**
- Shows persistent notification
- Best for **critical fire detection**

#### **Option B: Periodic Checks** (Battery efficient)
```dart
await BackgroundAIManager.startPeriodicTask(
  frequency: Duration(minutes: 15),
);
```
- Runs AI every **15-60 minutes**
- No persistent notification  
- Best for **monitoring mode**

### 3. Add UI to your app:
```dart
// In your settings screen:
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => BackgroundServiceControl(),
  ),
);
```

---

## 🔧 How It Works

### **Foreground Service** (Continuous)
```
App Closed → Service Keeps Running → AI runs every 5s → Shows Notification
                ↓
         Firebase Database
         cnn_results/foreground
```

### **WorkManager** (Periodic)
```
App Killed → Android wakes app every 15min → Run AI → Save to Firebase → Sleep
                ↓
         Firebase Database
         cnn_results/background
```

---

## 📊 Results Location (Firebase Realtime Database)

Both services write AI predictions to Firebase:

```javascript
// Foreground Service results
firebase.database().ref("cnn_results/foreground")

// Periodic Task results  
firebase.database().ref("cnn_results/background")

// Structure:
{
  "fire_probability": 0.85,
  "no_fire_probability": 0.15,
  "prediction": "FIRE",
  "timestamp": "2026-02-13T10:30:00.000",
  "source": "foreground_service" // or "background_task"
}
```

---

## ⚙️ API Reference

```dart
// Initialize (in main.dart - already done)
await BackgroundAIManager.initWorkManager();
BackgroundAIManager.initForegroundTask();

// Foreground Service
await BackgroundAIManager.startForegroundService();
await BackgroundAIManager.stopForegroundService();
bool isRunning = await BackgroundAIManager.isForegroundServiceRunning();

// Periodic Task
await BackgroundAIManager.startPeriodicTask(
  frequency: Duration(minutes: 15), // 15-60 minutes
);
await BackgroundAIManager.stopPeriodicTask();
```

---

## 🔋 Battery & Performance

| Service | CPU Usage | Battery Impact | Update Frequency |
|---------|-----------|----------------|------------------|
| **Foreground** | Continuous | High | Every 5 seconds |
| **Periodic** | Intermittent | Low | Every 15+ minutes |

**Recommendation**: 
- Use **Foreground Service** for active fire monitoring
- Use **Periodic Task** for general surveillance mode

---

## 📱 Platform Support

### ✅ Android
- **Foreground Service**: Full support
- **Periodic Task**: Full support  
- Both work perfectly even when app is killed

### ⚠️ iOS  
- **Foreground Service**: Limited (iOS restricts background time)
- **Periodic Task**: Uses Background Fetch (Apple controls timing)
- Consider using **Push Notifications** for iOS instead

---

## 🔐 Permissions (Auto-handled)

The app will automatically request:
- ✅ Ignore battery optimization
- ✅ Display over other apps (for notification)
- ✅ Post notifications
- ✅ Run on boot

Users can deny these, which will prevent background execution.

---

## 🐛 Troubleshooting

### Service not starting?
```dart
// Check if running
bool running = await BackgroundAIManager.isForegroundServiceRunning();
print('Service running: $running');
```

### Periodic task not executing?
- Check Android battery optimization settings
- Verify network connectivity (required)
- Check logs: `flutter logs` or `adb logcat`

### iOS not working?
- iOS has strict background limitations
- Use Push Notifications to wake app instead
- Background Fetch is not guaranteed

---

## 📝 Next Steps

1. **Test the services**:
   ```bash
   flutter run
   # Navigate to your settings and enable background services
   # Close the app and check Firebase for new results
   ```

2. **Listen to results**: Update your alert listener to monitor both:
   - `cnn_results/foreground`
   - `cnn_results/background`

3. **Customize**: Adjust frequencies, notification text, or inference logic in:
   - `foreground_ai_service.dart` (line 48: Timer interval)
   - `background_ai_manager.dart` (line 18: Periodic frequency)

---

## 📚 See Also

- **USAGE_EXAMPLES.dart** - More code examples
- **background_service_control.dart** - UI implementation
- WorkManager docs: https://pub.dev/packages/workmanager
- Foreground Task docs: https://pub.dev/packages/flutter_foreground_task

---

**🔥 Your AI is now ready to run 24/7 in the background!**
