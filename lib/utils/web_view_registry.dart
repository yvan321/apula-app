// lib/utils/web_view_registry.dart
//
// ✅ Provides safe access to platformViewRegistry for Flutter Web (3.22+)

import 'package:flutter/foundation.dart' show kIsWeb;

// ✅ import at top (not inside function)
import 'dart:ui_web' as ui_web;

dynamic getPlatformViewRegistry() {
  if (kIsWeb) {
    return ui_web.platformViewRegistry;
  }
  return null;
}
