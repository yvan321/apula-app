import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

/// Returns the correct base URL for your backend depending on where the app runs.
///
/// - 🧱 Android Emulator → http://10.0.2.2:3000  
/// - 📱 Real Android Device → http://192.168.1.8:3000 (your computer's IP)  
/// - 💻 Flutter Web → http://localhost:3000
///
/// Make sure your Node.js server is running on port 3000 and that both
/// your phone and PC are on the same Wi-Fi.
Future<String> getBaseUrl() async {
  if (kIsWeb) return "http://localhost:3000";

  if (Platform.isAndroid) {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    // Check for emulator indicators
    bool isEmulator = androidInfo.isPhysicalDevice == false ||
        androidInfo.brand.toLowerCase().contains("generic") ||
        androidInfo.model.toLowerCase().contains("sdk") ||
        androidInfo.device.toLowerCase().contains("emulator");

    if (isEmulator) {
      return "http://10.0.2.2:3000"; // 🧱 Emulator
    } else {
      return "http://192.168.1.8:3000"; // 📱 Real phone (replace with your PC's IP)
    }
  }

  // Fallback for other platforms (iOS, desktop)
  return "http://192.168.1.8:3000";
}
