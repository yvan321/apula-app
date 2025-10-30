// lib/utils/platform_view_registry.dart

// This safely exposes `platformViewRegistry` only on web.

import 'package:flutter/foundation.dart' show kIsWeb;

typedef PlatformViewRegistryRegister = void Function(
  String viewTypeId,
  dynamic Function(int) viewFactory,
);

PlatformViewRegistryRegister? getPlatformViewRegistry() {
  if (kIsWeb) {
    // ignore: avoid_web_libraries_in_flutter
    import 'dart:ui' as ui;
    // ignore: undefined_prefixed_name
    return ui.platformViewRegistry.registerViewFactory;
  }
  return null;
}
