# Background Services Testing Guide

## 🎯 How to Verify Background Services are Working

### 1. **Test Foreground Service (Continuous Monitoring)**

**What it does:**
- Runs AI inference every 5 seconds
- Shows persistent notification even when app is closed
- Updates notification with fire detection results

**How to verify:**

1. Open the app → Go to **Background Service Control** screen
2. Tap **"Start Service"** under "Continuous Monitoring"
3. Look for notification: **"APULA AI Monitoring"**
4. Close the app completely (swipe away from recent apps)
5. **You should still see the notification** - it will update every 5 seconds with results like:
   - `NO_FIRE - Fire: 12.5%`
   - `FIRE - Fire: 87.3%` (if fire detected)

**Expected behavior:**
- ✅ Notification stays visible when app is closed
- ✅ Notification text updates every 5 seconds
- ✅ Tapping notification reopens the app
- ✅ Check Firebase Realtime Database → `cnn_results/foreground` for latest predictions

---

### 2. **Test Periodic Task (Every 15 minutes)**

**What it does:**
- Runs in background every 15 minutes (even when app is killed)
- Shows notification when task runs
- More battery efficient than continuous monitoring

**How to verify:**

1. Open the app → Go to **Background Service Control** screen
2. Tap **"Enable"** under "Periodic Check (Every 15 min)"
3. Close the app completely
4. **Wait 15 minutes** (or less for testing - WorkManager may run sooner)
5. You should receive notifications:
   - `🔥 APULA Background Task - Running AI analysis...`
   - `🔥 AI Detection Result - NO_FIRE - Fire: 12.5%`

**Expected behavior:**
- ✅ Notifications appear even when app is killed
- ✅ Check Firebase Realtime Database → `cnn_results/background` for task results
- ✅ Task runs every 15 minutes automatically

---

### 3. **Test Notifications**

If you want to verify notifications are working without waiting:

1. Go to **Background Service Control** screen
2. Tap **"Send Test Notification"** (orange button)
3. You should see: `🔔 Test Notification - If you see this, notifications are working!`

**Troubleshooting:**
- If no notification appears, check **Settings → Apps → APULA → Notifications** - make sure they're enabled
- Grant "Display over other apps" permission if prompted
- Disable battery optimization for APULA app

---

## 📊 Checking Results in Firebase

### Firebase Realtime Database Structure:

```
cnn_results/
  ├── foreground/           ← Results from continuous service
  │   ├── fire_probability
  │   ├── no_fire_probability
  │   ├── prediction        (FIRE or NO_FIRE)
  │   ├── timestamp
  │   └── source            (foreground_service)
  │
  └── background/           ← Results from periodic task
      ├── fire_probability
      ├── no_fire_probability
      ├── prediction
      ├── timestamp
      └── source            (background_task)
```

### How to check:

1. Open Firebase Console → Realtime Database
2. Navigate to `cnn_results`
3. Check timestamps to verify when services ran
4. Compare `foreground` vs `background` results

---

## 🔋 Battery Impact

| Service Type | Battery Usage | When to Use |
|--------------|---------------|-------------|
| **Foreground Service** | High (runs every 5 seconds) | When you need real-time monitoring |
| **Periodic Task** | Low (runs every 15 min) | For regular checks without draining battery |

**Recommendation:** Use Foreground Service only when actively monitoring. Use Periodic Task for 24/7 protection with minimal battery drain.

---

## 🐛 Common Issues

### Issue: "No notification appears"
**Solution:**
- Check notification permissions: Settings → Apps → APULA → Notifications
- Make sure app isn't being killed by battery saver
- Go to Settings → Battery → APULA → "Don't optimize"

### Issue: "Service stops when app is closed"
**Solution:**
- Grant "Display over other apps" permission
- Disable battery optimization
- Check if phone manufacturer has aggressive battery management (Xiaomi, Huawei, etc.)
  - Xiaomi: Settings → Battery & performance → Manage apps' battery usage → APULA → No restrictions

### Issue: "Periodic task doesn't run after 15 minutes"
**Solution:**
- WorkManager timing is approximate - Android optimizes for battery
- Task may run between 15-30 minutes depending on device state
- Check Firebase to see actual run times

### Issue: "Notifications work but no data in Firebase"
**Solution:**
- Make sure Firebase is initialized in `main.dart`
- Check internet connection
- Verify Firebase Realtime Database rules allow writes
- Check console logs for errors: `flutter logs`

---

## 📱 Platform Differences

### Android:
- ✅ Both services fully supported
- ✅ Foreground service shows persistent notification
- ✅ Periodic task works even when app is killed

### iOS:
- ⚠️ Background execution is more restricted
- ⚠️ Periodic tasks may not work reliably
- ⚠️ Use "Background App Refresh" in iOS settings

---

## 🔍 Debug Logs

When services are running, you'll see console logs:

```
🚀 Foreground AI Service Started
🔥 AI: NO_FIRE (12.5%)
🔥 AI: NO_FIRE (11.8%)
...

🔥 Background AI Task Started: periodicAITask
🔥 AI Result: NO_FIRE (Fire: 13.2%)
✅ Background AI Task Completed
```

Run `flutter logs` in terminal to see these logs even when app is closed.

---

## 🎯 Quick Test Checklist

- [ ] Test notification button works
- [ ] Start foreground service → notification appears
- [ ] Close app → notification still visible
- [ ] Notification text updates every 5 seconds
- [ ] Check Firebase `cnn_results/foreground` has data
- [ ] Enable periodic task
- [ ] Wait 15 minutes → notification appears
- [ ] Check Firebase `cnn_results/background` has data
- [ ] Both services can run simultaneously

---

**Need Help?** Check the console logs with `flutter logs` or inspect Firebase Realtime Database for service activity.
