import 'package:flutter/material.dart';

class MJpegView extends StatelessWidget {
  final String url;
  const MJpegView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Center(child: Text("Stream unavailable")),
    );
  }
}
