# APULA Flask App - Codebase Structure & Components

## 1. MAIN SCREENS LOCATION

All main screens are located under `lib/screens/app/`:

### **1.1 Home Page (Dashboard)**
- **File:** [lib/screens/app/home/home_page.dart](lib/screens/app/home/home_page.dart)
- **Description:** Main dashboard displaying real-time sensor data, alert history charts, and device status
- **Key Features:**
  - Time and date display with animation controller for weather visuals
  - Real-time temperature, fire detection, and smoke detection counters
  - Historical data tracking per camera with severity and alert scores
  - Multiple chart range options (day, week, month, year) via PageView
  - Activity log showing recent alerts (max 6 items)
  - Chart data persisted with configurable history limits (10,000 max points, 30-day lookback)
  - Alert thresholds: Pre-fire (0.20), Smoldering (0.40), Ignition (0.60), Developing (0.80)
  - Integrates with `CnnListenerService` for real-time CNN inference results

### **1.2 Live Footage / Camera View**
- **File:** [lib/screens/app/live/livefootage_page.dart](lib/screens/app/live/livefootage_page.dart)
- **Description:** Navigation hub for live camera feeds and thermal views
- **Related:** [lib/screens/app/live/live_camera_view_page.dart](lib/screens/app/live/live_camera_view_page.dart)
- **Key Features:**
  - Displays available linked cameras
  - WebView-based video playback for HLS/MJPEG streams
  - Dual feed support: CCTV and Thermal camera feeds
  - Fetches streams from Firebase Realtime Database (`cloudflare/{cameraId}/video_feed`)
  - Fullscreen toggle capability
  - Android WebView video playback enabled via `setMediaPlaybackRequiresUserGesture(false)`

### **1.3 Notification/Alert History Page**
- **File:** [lib/screens/app/notification/notification_page.dart](lib/screens/app/notification/notification_page.dart)
- **Description:** View and manage all fire detection alerts with filtering, read/unread status, and deletion
- **Key Features:**
  - Filters: All, Unread, Read alerts
  - Firestore data source: `user_alerts` collection
  - Deep linking from push notifications (handled via `_handleDeepLinkAlert()`)
  - Alert details modal showing: device name, severity score, alert score, snapshot image, dominant source
  - Per-alert actions:
    - Mark as read/unread
    - Delete individual alert
    - Delete all alerts with confirmation
  - Auto-marks alerts as read when viewing details
  - Incident classification: alerts with severity ≥ 0.70 and alert ≥ 0.80
  - Dismissible tiles with swipe-to-delete (endToStart direction)
  - Alert card styling: unread alerts have secondary warm color background
  - Timestamp formatting: "Just now", "Xm ago", "Xh ago", "Xd ago", or formatted date

### **1.4 Settings Page**
- **File:** [lib/screens/app/settings/settings_page.dart](lib/screens/app/settings/settings_page.dart)
- **Related:**
  - [lib/screens/app/settings/account_settings_page.dart](lib/screens/app/settings/account_settings_page.dart)
  - [lib/screens/app/settings/notifsetting_page.dart](lib/screens/app/settings/notifsetting_page.dart)
  - [lib/screens/app/settings/about_page.dart](lib/screens/app/settings/about_page.dart)
- **Description:** Settings navigation hub with theme, notifications, account, and app info
- **Key Features:**
  - Displays logged-in user name and email
  - Theme toggle (light/dark mode) via `ThemeProvider`
  - Profile data fetched from Firestore `users` collection

### **1.5 CNN Test Page (Fire Demo)**
- **File:** [lib/screens/demo/fire_demo_page.dart](lib/screens/demo/fire_demo_page.dart)
- **Description:** Demo/testing page for CNN model inference testing
- **Note:** Integration point for testing ML model outputs

### **1.6 Main Navigation Screen**
- **File:** [lib/screens/main_screen.dart](lib/screens/main_screen.dart)
- **Description:** Bottom navigation host coordinating all 5 main screens
- **Screens in order:**
  1. Home (HomePage)
  2. Camera (CameraPage placeholder)
  3. Activity (Placeholder for activity)
  4. Settings (Placeholder for settings)
  5. CNN Test (FireDemoPage)
- **Navigation:** BottomNavigationBar with 5 tabs, AppBar title updates per tab

---

## 2. PUSH NOTIFICATION RELATED CODE & SERVICES

### **2.1 FCM Service (Main Notification Handler)**
- **File:** [lib/services/fcm_service.dart](lib/services/fcm_service.dart)
- **Description:** Firebase Cloud Messaging initialization and push notification handling
- **Key Methods:**
  - `initialize()` - Requests notification permissions, gets FCM token, sets up listeners
  - `_saveFcmToken(token)` - Stores FCM token in Firestore `users` collection
  - `_handleForegroundMessage()` - Displays local notifications when app is in foreground
  - `_handleMessageOpenedApp()` - Navigates to alert details when notification is tapped
  - `_showLocalNotification()` - Creates local notification using `flutter_local_notifications`
- **Permission Levels:** alert, badge, sound (all enabled except announcement, critical alert)
- **Token Refresh:** Listens for `onTokenRefresh` and updates Firestore

### **2.2 Global Alert Handler (Alert Modal & Snooze Logic)**
- **File:** [lib/services/global_alert_handler.dart](lib/services/global_alert_handler.dart)
- **Description:** Centralized alert management with modal display, snooze, and fire escalation logic
- **Key Methods:**
  - `showFireModal()` - Main entry point for alert processing
  - `_createUserAlert()` - Logs alert to Firestore `user_alerts` collection
  - `_createDispatcherAlert()` - Sends alert to Firestore `alerts` collection (for emergency dispatch)
  - `_showHighModal()` - Extreme fire danger modal (auto-dispatch)
  - `_showMediumModal()` - Confirmation required modal
  - `_shouldShowModalFor()` - Rate limiting for modal display (30-second cooldown)
- **Key Constants:**
  - `modalCooldown`: 30 seconds between modals
  - `cautionSnoozeDuration`: 5 minutes snooze for caution-level alerts
  - `requiredStableCycles`: 2 (stability counter for escalations)
- **Modal Types:**
  - HIGH/DANGEROUS: Auto-dispatch when severity ≥ 0.90 AND alert ≥ 0.70
  - MEDIUM/CONFIRMATION: User action needed when severity ≥ 0.70 AND alert ≥ 0.40
  - LOW/CAUTION: Suppressible alert (snooze for 5 minutes) when severity ≥ 0.46 AND alert ≥ 0.60

### **2.3 Alert Service (Firestore Storage)**
- **File:** [lib/services/alert_service.dart](lib/services/alert_service.dart)
- **Description:** Low-level alert persistence to Firestore
- **Key Collections:**
  - `user_alerts` - User-facing alerts (medium/high severity)
  - `alerts` (dispatcher) - Emergency dispatcher alerts
- **Methods:**
  - `sendUserAlert()` - Stores user alert with device, severity, alert, snapshot URL
  - `sendDispatcherAlert()` - Stores dispatcher alert with user metadata, location, status

### **2.4 CNN Listener Service (Real-time CNN Results)**
- **File:** [lib/services/cnn_listener_service.dart](lib/services/cnn_listener_service.dart)
- **Description:** Subscribes to real-time CNN inference results from Firebase Realtime Database
- **Triggers:** Calls `GlobalAlertHandler.showFireModal()` when CNN results arrive
- **Feeds:** Receives alert and severity scores for each camera

---

## 3. EMAIL ALERT SENDING LOGIC

### **3.1 Backend Email Service (Node.js)**
- **File:** [functions/apula-server/server.js](functions/apula-server/server.js)
- **Description:** Express.js server handling email notifications via SMTP and Resend API
- **Key Endpoints:**
  - `POST /send-verification` - Sends verification codes during registration
  - Configurable email providers: Resend API (primary) or SMTP (fallback)
- **Email Configuration (Environment Variables):**
  - `RESEND_API_KEY` - Resend service API key
  - `SMTP_HOST` - SMTP server (default: smtp.gmail.com)
  - `SMTP_PORT` - SMTP port (default: 587)
  - `SMTP_SECURE` - Use TLS/SSL (default: false)
  - `EMAIL_USER` - SMTP username
  - `EMAIL_PASS` - SMTP password
  - `EMAIL_FROM` - Sender email address (default: alerts@example.com)
  - `APULA_EMAIL_ENABLED` - Master enable/disable flag
  - `EMAIL_COOLDOWN_SECONDS` - Rate limiting (default: 180 seconds)

### **3.2 Email Configuration Files**
- **File:** [functions/.env.apula-36cee](functions/.env.apula-36cee)
- **Sample settings:**
  ```
  APULA_EMAIL_ENABLED=true
  EMAIL_COOLDOWN_SECONDS=180
  EMAIL_FROM=alerts@example.com
  ```

### **3.3 Email Integration in Backend**
- **File:** [functions/index.js](functions/index.js)
- **Description:** Cloud Functions entry point for alert processing
- **Related:** [functions/sendAlertNotification.js](functions/sendAlertNotification.js)
- **Note:** Email sending is controlled via environment flags and cooldown periods

---

## 4. ALERT/ACTIVITY HISTORY STORAGE & RETRIEVAL

### **4.1 Firestore Collections**

#### **User Alerts** (`user_alerts`)
- **Schema:**
  ```
  {
    type: string,              // "Severe Fire Risk", "Possible Fire", custom alerts
    deviceName: string,        // Camera/device identifier
    snapshotUrl: string,       // URL to snapshot image
    snapshot_base64: string,   // Optional base64 encoded image
    alert: double,             // Alert confidence score (0-1)
    severity: double,          // Severity score (0-1)
    dominantSource: string,    // "cctv", "sensor", "mixed"
    sourceLabel: string,       // Humanized source ("CCTV / Vision", etc)
    timestamp: Timestamp,      // Server-side timestamp
    read: boolean,             // User read status
    userId: string,            // User ID filter
    userEmail: string,         // User email filter
  }
  ```

#### **Dispatcher Alerts** (`alerts`)
- **Schema:**
  ```
  {
    type: string,              // "🔥 Fire Detected", etc
    location: string,          // Device/location name
    description: string,       // Event description
    snapshotUrl: string,       // Evidence image
    dominantSource: string,    // Alert source type
    sourceLabel: string,       // Humanized source
    status: string,            // "Pending", "Resolved", etc
    timestamp: Timestamp,      // Server-side
    read: boolean,             // Dispatcher read status
    userName: string,          // User details
    userAddress: string,
    userContact: string,
    userEmail: string,
    userLatitude: number,
    userLongitude: number,
  }
  ```

#### **CNN History** (`cnn_history/{cameraId}/points`)
- **Schema:**
  ```
  {
    ts: Timestamp,             // Timestamp of inference
    severity: double,          // Computed severity
    alert: double,             // Computed alert score
    // Additional raw sensor values
  }
  ```
- **Query Strategy:** Lookback 30 days, max 10,000 points, 5-minute sample interval
- **Location in Code:** [lib/screens/app/home/home_page.dart](lib/screens/app/home/home_page.dart) `_loadHistoryForCamera()`

### **4.2 Real-time Database (YOLO Firebase)**
- **Location:** Firebase Realtime Database (secondary instance for YOLO processing)
- **Paths:**
  - `sensor_data/{cameraId}/latest` - Latest sensor readings
  - `cloudflare/{cameraId}/video_feed` - Live CCTV URL
  - `cloudflare/{cameraId}/thermalfeed` - Thermal camera URL

### **4.3 History Retrieval Methods**

#### **In-Memory History (HomePage)**
- Maintains per-camera maps:
  - `severityHistoryPerCamera` - List of severity values
  - `alertHistoryPerCamera` - List of alert scores
  - `historyTimestampsPerCamera` - Corresponding timestamps
- Max 10,000 points per camera, oldest removed first
- Used for displaying charts on HomePage

#### **Firestore Query (NotificationPage)**
- Filters by user ID or email
- Supports deep-linking via alert ID from push notifications
- Can query single alert or all alerts with filtering

### **4.4 Background History Collection**
- **File:** [lib/services/background_ai_manager.dart](lib/services/background_ai_manager.dart)
- Periodic collection via WorkManager (15-minute intervals)
- Foreground task option for continuous monitoring

---

## 5. SNOOZE & ALERT CONDITION LOGIC

### **5.1 Snooze Implementation**
- **File:** [lib/services/global_alert_handler.dart](lib/services/global_alert_handler.dart)
- **State Variable:** `_cautionSnoozeUntil` (DateTime nullable)
- **Snooze Duration:** 5 minutes (`Duration(minutes: 5)`)

#### **Snooze Logic Flow:**
1. When caution-level alert detected, snooze countdown starts
2. User sees "Snooze: X:XX" button on confirmation modal
3. Clicking snooze sets `_cautionSnoozeUntil = DateTime.now().add(snoozeSeconds)`
4. During snooze period, caution alerts are suppressed (checked via `_shouldShowModalFor()`)
5. After snooze expires, caution alerts resume

#### **Snooze Button Behavior:**
- Displays dynamic countdown: "Snooze: 4:58", "Snooze: 4:57", etc
- Decrements every second when modal is open
- Different snooze durations based on modal type (5 min default)

### **5.2 Alert Condition Logic**

#### **Alert Escalation Levels** (in `showFireModal()`)

1. **CAUTION (Yellow)** 
   - Condition: `(severity >= 0.46 && alert >= 0.60) || (severity >= 0.55 && alert >= 0.45)`
   - Suppressible via 5-minute snooze
   - Non-blocking modal

2. **CONFIRMATION (Orange)**
   - Condition: `(severity >= 0.70 && alert >= 0.40) || (severity >= 0.95 && alert >= 0.55)`
   - Requires user action (confirm or dismiss)
   - Shows confirmation modal
   - Single high spike trigger: `(severity >= 0.90 || alert >= 0.90) && !(severity >= 0.90 && alert >= 0.90)`

3. **DANGEROUS (Red)**
   - Condition: `severity >= 0.90 && alert >= 0.70`
   - Auto-dispatches to emergency responders
   - Blocking modal (cannot snooze)
   - Highest priority alert

#### **Stability Counters**
- `_dangerCounter` - Incremented each cycle dangerous condition met
- `_confirmationCounter` - Incremented each cycle confirmation condition met
- `requiredStableCycles = 2` - Must be stable for 2 consecutive cycles before escalation
- Prevents false positives from single-frame anomalies

#### **Feedback Thresholds** (from HomePage)
- Pre-Fire (0.20), Smoldering (0.40), Ignition (0.60), Developing (0.80)
- Used for activity log classification

#### **Rate Limiting**
- `_lastModalTime` and `_lastModalType` - Track previous modals
- `modalCooldown = 30 seconds` - Minimum time between modals of same type
- Prevents modal spam

#### **Reset Logic**
- If not dangerous AND not confirmation AND not caution, incident is resolved
- `_dispatcherAlertSent` flag reset, assuming dispatcher has taken action
- All counters reset

### **5.3 Modal Snooze Preview**
- Shows user the snooze duration countdown
- Updates every second via Timer in modal
- "Snooze" button text shows remaining seconds
- On dismiss/confirm, snooze is set/cancelled accordingly

---

## 6. UI COMPONENTS: CARDS, BUTTONS, FONTS & THEME

### **6.1 Theme & Font Configuration**
- **File:** [lib/main.dart](lib/main.dart) (lines 137-250)
- **Theme Provider:** [lib/providers/theme_provider.dart](lib/providers/theme_provider.dart)

#### **Text Theme (Font Sizes)**
- **`headlineLarge`**: 34px, w700 (bold)
- **`headlineMedium`**: 30px, w700
- **`headlineSmall`**: 26px, w600 (semi-bold)
- **`titleLarge`**: 24px, w600
- **`titleMedium`**: 20px, w600
- **`bodyLarge`**: 18px, w600, line-height 1.4
- **`bodyMedium`**: 16px (standard body text), line-height 1.4
- **`bodySmall`**: 14px, line-height 1.35
- **`labelLarge`**: 16px, w600
- **`labelMedium`**: 14px

#### **Color Palette**
- **File:** [lib/utils/app_palette.dart](lib/utils/app_palette.dart)
- **Fire/Primary Colors:**
  - `primaryFire`: #EA580C (Burnt orange - brand color)
  - `secondaryWarm`: #F59E0B (Amber - secondary actions)
  - `highlightHeat`: #FCD34D (Light amber - highlights)
- **Functionality Colors:**
  - `actionTeal`: #2EC4B6 (Primary buttons/actions)
  - `emergencyRed`: #DC2626 (Emergency alerts, destructive actions)
- **Background Colors:**
  - Light: White (#FFFFFF)
  - Dark: #121212 (Material 3)
- **Card Colors:**
  - Light: #F5F5F5
  - Dark: #1E1E1E

### **6.2 Common UI Components**

#### **Buttons**
- **ElevatedButton**
  - Background: actionTeal (#2EC4B6)
  - Foreground: White
  - Min Height: 52px
  - Text Style: 16px, w600
  - Usage: Primary actions (confirm, submit)

- **TextButton**
  - Foreground: scheme.tertiary (actionTeal)
  - Usage: Secondary/dismissible actions

- **OutlinedButton.icon**
  - Used in manual alert flow for device selection
  - Usage: Select/change device for manual dispatch

- **FilledButton**
  - Same styling as ElevatedButton
  - Alternative Material 3 approach

#### **Cards**
- **Card**
  - Material 3 styled with elevation
  - Background: cardColor (scheme.surface)
  - Border Radius: 15-18px
  - Rounded corners on AlertDialog
  - Example: Alert notification tiles, settings panels

- **Container with Padding**
  - Generic padding: `EdgeInsets.all(16)` standard
  - Used for sections and grouping

#### **Input Components**
- **InputDecorationTheme**
  - Fill Color: #F0F0F0 (light mode)
  - Border Radius: 12px
  - Content Padding: horizontal 16, vertical 16

- **DropdownButtonFormField**
  - Used in manual alert for device selection
  - Styling inherits from InputDecorationTheme

- **TextFormField**
  - Standard input for alert descriptions/details

#### **Advanced Components**
- **BottomNavigationBar** (main_screen.dart)
  - 5 tabs with icons
  - Selected color: #A30000 (red)
  - Unselected: grey
  - Type: fixed (all visible)

- **BottomSheet**
  - Alert options menu (mark read, delete)
  - Rounded top border: BorderRadius 18px
  - SafeArea wrapper for notch safety

- **FloatingActionButton.extended**
  - Manual alert trigger button (global)
  - Positioned above bottom nav
  - Custom icon and label

- **AlertDialog**
  - Confirmation dialogs (delete all alerts, etc)
  - Rounded corners: 15px
  - Title: Large, bold, error color for destructive dialogs

- **Dismissible**
  - Alert tiles swipe-to-delete
  - Direction: endToStart (swipe left)
  - Red delete background

- **WebView**
  - Live camera feed display
  - JavaScript enabled
  - Media playback without user gesture (Android)

### **6.3 Widget Examples**

#### **Alert Notification Tile** (notification_page.dart)
- Background: `secondaryWarm.withOpacity(isDark ? 0.18 : 0.14)` if unread
- Border: secondaryWarm if unread, else subtle
- Left icon tile: device/alert icon
- Right info: device name, severity, alert score, timestamp
- Swipe-to-delete: red background "Delete"
- Clickable: opens detail modal

#### **Settings Card** (settings_page.dart)
- Padding: 16px
- Title + value format
- Background: Card color
- Icons: Material icons

#### **Manual Alert Modal**
- Device dropdown
- Alert type field
- Snooze/dismiss buttons
- Confirmation: "Report Fire" (elevated)
- Cancellation: Text button

---

## 7. SERVICES ORGANIZATION

### **7.1 Authentication Services**
- **File:** [lib/services/auth_service.dart](lib/services/auth_service.dart)
- Handles user login, registration, verification

### **7.2 CNN Inference Services**
- **CnnService** [lib/services/cnn_service.dart](lib/services/cnn_service.dart)
  - Loads TensorFlow Lite model: `assets/models/APULA_FUSION_CNN_v2.tflite`
  - Loads feature scaler: `assets/models/feature_scaler.json`
  - Runs inference with 10 inputs: YOLO confidence, temperature, humidity, smoke PPM, flame, thermal max/avg, YOLO outputs
  - Returns: severity and alert scores

- **CnnListenerService** [lib/services/cnn_listener_service.dart](lib/services/cnn_listener_service.dart)
  - Real-time listener on Firebase Realtime DB for CNN results
  - Triggers alert modals

- **BackgroundCnnService** [lib/services/background_cnn_service.dart](lib/services/background_cnn_service.dart)
  - Background inference when app is not active
  - WorkManager integration

### **7.3 Background Task Services**
- **BackgroundAIManager** [lib/services/background_ai_manager.dart](lib/services/background_ai_manager.dart)
  - Periodic task scheduling (15-minute intervals)
  - Foreground service for continuous monitoring
  - WorkManager configuration

- **BackgroundAITask** [lib/services/background_ai_task.dart](lib/services/background_ai_task.dart)
  - Actual background inference execution

- **ForegroundAIService** [lib/services/foreground_ai_service.dart](lib/services/foreground_ai_service.dart)
  - Continuous monitoring when app is active

### **7.4 Global Services**
- **GlobalAlertHandler** [lib/services/global_alert_handler.dart](lib/services/global_alert_handler.dart)
  - Centralized alert orchestration
  - Modal management
  - Firestore persistence

---

## 8. WIDGET ORGANIZATION

- **GlobalManualAlertButton** [lib/widgets/global_manual_alert_button.dart](lib/widgets/global_manual_alert_button.dart)
  - Floating action button for manual alert triggering
  - Device selection dropdown
  - Alert type and description input

- **BackgroundServiceControl** [lib/widgets/background_service_control.dart](lib/widgets/background_service_control.dart)
  - Control panel for background monitoring services
  - Start/stop periodic tasks
  - Foreground service status

- **CustomBottomNav** [lib/widgets/custom_bottom_nav.dart](lib/widgets/custom_bottom_nav.dart)
  - Bottom navigation bar component

---

## Dependencies & Key Libraries

### **Firebase & Backend**
- `firebase_core`, `firebase_auth`, `cloud_firestore`
- `firebase_database`, `firebase_storage`, `firebase_messaging`
- `cloud_functions`

### **UI Packages**
- `provider` - State management
- `flutter_local_notifications` - Local notifications
- `fl_chart` - Chart visualization
- `lottie` - Animations

### **ML & Image Processing**
- `tflite_flutter` - TensorFlow Lite inference
- `camera`, `image_picker` - Camera/image capture

### **Other**
- `permission_handler`, `geolocator` - Permissions & location
- `webview_flutter` - WebView for streaming
- `workmanager` - Background tasks
- `flutter_foreground_task` - Foreground services
- `shared_preferences` - Local preferences

---

## Key Configuration Files

- **pubspec.yaml** - Dependencies and SDK requirements (Flutter 3.19.6+)
- **firebase_options.dart** - Firebase configuration for prod/dev
- **firebase_yolo_options.dart** - Secondary YOLO Firebase instance
- **analysis_options.yaml** - Lint configuration
- **DEPLOYMENT.md** - Environment variable setup
- **BACKGROUND_SERVICES_GUIDE.md** - Background service architecture
- **BACKGROUND_AI_SETUP.md** - ML backend setup

