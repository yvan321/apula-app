import 'dart:io';
import 'package:flutter/material.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../main.dart';

class LiveFootagePage extends StatefulWidget {
  final List<String> devices;

  const LiveFootagePage({super.key, required this.devices});

  @override
  State<LiveFootagePage> createState() => _LiveFootagePageState();
}

class _LiveFootagePageState extends State<LiveFootagePage> {
  int _selectedIndex = 1; // 📍 'Live' tab is selected

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        // Stay on Live
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/notifications');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  // 🔥 Loading dialog before opening camera view
  void _showLoadingDialog(String cameraId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              width: 400,
              child: Lottie.asset('assets/fireloading.json', repeat: true),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                "Opening $cameraId...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA30000),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Simulate connecting, then navigate
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        Navigator.pushNamed(
          context,
          '/live_camera_view',
          arguments: {
            "deviceName": cameraId,
            "cameraId": cameraId,
          },
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔙 Custom Back Button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),

            // 📌 Main Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✨ Title
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        "Live Footage",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // 📹 Device List / No Devices
                    Expanded(
                      child: widget.devices.isEmpty
                          ? _buildNoDevices(context)
                          : _buildDeviceList(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // ➕ Floating “Add Device” button
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/add_device');
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),

      // 🔽 Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: widget.devices,
      ),
    );
  }

  /// Widget if there are no devices
  Widget _buildNoDevices(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.videocam_off, size: 80, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            "No Devices Available",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// Widget if devices exist
  Widget _buildDeviceList(BuildContext context) {
    return ListView.builder(
      itemCount: widget.devices.length,
      itemBuilder: (context, index) {
        final cameraId = widget.devices[index];
        return _CameraPreviewCard(
          cameraId: cameraId,
          onTap: () => _showLoadingDialog(cameraId),
        );
      },
    );
  }
}

// 📹 Camera Preview Card with Live Feed
class _CameraPreviewCard extends StatefulWidget {
  final String cameraId;
  final VoidCallback onTap;

  const _CameraPreviewCard({
    required this.cameraId,
    required this.onTap,
  });

  @override
  State<_CameraPreviewCard> createState() => _CameraPreviewCardState();
}

class _CameraPreviewCardState extends State<_CameraPreviewCard> {
  late final WebViewController _webViewController;
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadVideoFeed();
  }

  void _initWebView() {
    final params = PlatformWebViewControllerCreationParams();
    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    if (Platform.isAndroid) {
      final androidController =
          _webViewController.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _loadVideoFeed() {
    final ref = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/video_feed");

    ref.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      if (url != null && mounted && !_videoLoaded) {
        _videoLoaded = true;
        final html = '''
          <!DOCTYPE html>
          <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body {
                margin: 0;
                padding: 0;
                background: black;
                width: 100%;
                height: 100%;
                overflow: hidden;
              }
              img {
                width: 100%;
                height: 100%;
                object-fit: cover;
              }
            </style>
          </head>
          <body>
            <img src="$url" alt="Camera Feed" />
          </body>
          </html>
        ''';
        _webViewController.loadHtmlString(html);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Container(
                height: 180,
                color: Colors.black,
                child: Stack(
                  children: [
                    // Live video preview
                    if (_videoLoaded)
                      WebViewWidget(controller: _webViewController)
                    else
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    // LIVE badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA30000),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.circle,
                              color: Colors.white,
                              size: 8,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cameraId,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            Icon(
                              Icons.wifi,
                              size: 14,
                              color: Colors.green,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
