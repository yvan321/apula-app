import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

/// 🌐 PRODUCTION URL - Deploy your backend to Railway/Render/Heroku and update this
/// Example: "https://apula-backend.railway.app"
const String PRODUCTION_URL = "https://apula-app-production.up.railway.app";

/// 🏠 LOCAL IP - Your computer's IP for local development
const String LOCAL_IP = "192.168.1.4";
const int LOCAL_PORT = 3007;

/// Returns the correct base URL for your backend depending on where the app runs.
///
/// **PRODUCTION MODE** (Release build):
/// - Uses PRODUCTION_URL
///
/// **DEVELOPMENT MODE** (Debug build):
/// - 🧱 Android Emulator → http://10.0.2.2:3007  
/// - 📱 Real Android Device → http://192.168.1.4:3007
/// - 💻 Flutter Web → http://localhost:3007
///
/// To switch to production, either:
/// 1. Build release APK/IPA (automatic)
/// 2. Set `kDebugMode = false` manually
Future<String> getBaseUrl() async {
  // 🚀 PRODUCTION MODE - use cloud backend
  if (!kDebugMode) {
    return PRODUCTION_URL;
  }

  // 🛠️ DEVELOPMENT MODE - use local server
  if (kIsWeb) return "http://localhost:$LOCAL_PORT";

  if (Platform.isAndroid) {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    // Check for emulator indicators
    bool isEmulator = androidInfo.isPhysicalDevice == false ||
        androidInfo.brand.toLowerCase().contains("generic") ||
        androidInfo.model.toLowerCase().contains("sdk") ||
        androidInfo.device.toLowerCase().contains("emulator");

    if (isEmulator) {
      return "http://10.0.2.2:$LOCAL_PORT"; // 🧱 Emulator
    } else {
      return "http://$LOCAL_IP:$LOCAL_PORT"; // 📱 Real phone
    }
  }

  // Fallback for other platforms (iOS, desktop)
  return "http://$LOCAL_IP:$LOCAL_PORT";
}
