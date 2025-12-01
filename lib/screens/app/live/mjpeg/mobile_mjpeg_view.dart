import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MJpegView extends StatefulWidget {
  final String url;
  const MJpegView({super.key, required this.url});

  @override
  State<MJpegView> createState() => _MJpegViewState();
}

class _MJpegViewState extends State<MJpegView> {
  Uint8List? _frame;
  StreamSubscription<List<int>>? _sub;
  http.Client? _client;

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void didUpdateWidget(covariant MJpegView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.url != widget.url) {
      _stopStream();
      _startStream();
    }
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;

    _client?.close();
    _client = null;
  }

  Future<void> _startStream() async {
    _stopStream();

    _client = http.Client();
    final request = http.Request("GET", Uri.parse(widget.url));

    try {
      final response = await _client!.send(request);

      List<int> buffer = [];

      _sub = response.stream.listen(
        (chunk) {
          buffer.addAll(chunk);

          int start = -1;
          int end = -1;

          for (int i = 0; i < buffer.length - 1; i++) {
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) start = i;
            if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
              end = i + 2;
              break;
            }
          }

          if (start != -1 && end != -1 && end > start) {
            final frameBytes = Uint8List.fromList(buffer.sublist(start, end));

            if (mounted) {
              setState(() => _frame = frameBytes);
            }

            buffer = buffer.sublist(end);
          }
        },
        onError: (e) {
          print("MJPEG error: $e");
          if (mounted) setState(() => _frame = null);
          _reconnect();
        },
        onDone: () {
          if (mounted) setState(() => _frame = null);
          _reconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      print("MJPEG connect error: $e");
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _startStream();
    });
  }

  @override
  void dispose() {
    _stopStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frame == null) {
      return const Center(child: Text("Connecting to stream..."));
    }

    return Image.memory(
      _frame!,
      gaplessPlayback: true,
      fit: BoxFit.cover,
    );
  }
}
