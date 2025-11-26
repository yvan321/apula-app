// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class MJpegView extends StatelessWidget {
  final String url;
  const MJpegView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final viewId = "mjpeg-${url.hashCode}";

    // Register view for Web
    // ignore: undefined_prefixed_name
    platformViewRegistry.registerViewFactory(viewId, (int _) {
      final img = html.ImageElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover';

      return img;
    });

    return HtmlElementView(viewType: viewId);
  }
}
