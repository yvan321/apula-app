import 'package:flutter/material.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.videocam, size: 100, color: Colors.grey),
    );
  }
}
