import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  static const String _cameraDisplayNameKey = 'camera_display_names_v1';

  int _selectedIndex = 1; // 📍 'Live' tab is selected
  Map<String, String> _cameraDisplayNames = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadDisplayNames();
  }

  Future<void> _loadDisplayNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cameraDisplayNameKey);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (!mounted) return;
      setState(() {
        _cameraDisplayNames = map.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      });
    } catch (_) {
      // Keep defaults if parsing fails.
    }
  }

  String _displayNameFor(String cameraId) {
    final custom = _cameraDisplayNames[cameraId]?.trim();
    if (custom == null || custom.isEmpty) return cameraId;
    return custom;
  }

  Future<void> _saveDisplayNames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cameraDisplayNameKey,
      jsonEncode(_cameraDisplayNames),
    );
  }

  Future<void> _renameCameraDisplayName(String cameraId) async {
    final controller = TextEditingController(text: _displayNameFor(cameraId));

    final updatedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename Camera Display Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Display name',
            hintText: 'Example: Front Door Cam',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (updatedName == null || !mounted) return;

    setState(() {
      if (updatedName.isEmpty) {
        _cameraDisplayNames.remove(cameraId);
      } else {
        _cameraDisplayNames[cameraId] = updatedName;
      }
    });
    await _saveDisplayNames();
  }

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
        Navigator.pushReplacementNamed(context, '/predictions');
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/notifications');
        break;
      case 4:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  void _showLiveGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Live Footage Guide'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Tap Add camera, then scan the QR code shown on your APULA camera module.'),
            SizedBox(height: 8),
            Text('2. If you do not have a QR yet, open Devices Info to view your registered IDs and pair from there.'),
            SizedBox(height: 8),
            Text('3. After scanning/pairing, wait for the camera card preview to appear in this page.'),
            SizedBox(height: 8),
            Text('4. Tap a camera card to open full live view. Use Rename to set a friendly name.'),
            SizedBox(height: 8),
            Text('5. If preview stays loading, check camera power, Wi-Fi, and cloudflare/video_feed status.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<bool> _handleBackToHome() async {
    Navigator.pushReplacementNamed(context, '/home');
    return false;
  }

  // 🔥 Loading dialog before opening camera view
  void _showLoadingDialog(String cameraId, String displayName) {
    final primary = Theme.of(context).colorScheme.primary;
    final nav = Navigator.of(context, rootNavigator: true);

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
                "Opening $displayName...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Simulate connecting, then navigate
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;

      try {
        if (nav.canPop()) {
          nav.pop();
        }

        await Navigator.pushNamed(
          this.context,
          '/live_camera_view',
          arguments: {
            "deviceName": displayName,
            "cameraId": cameraId,
          },
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(this.context).showSnackBar(
            const SnackBar(content: Text('Unable to open live camera view right now.')),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackToHome,
      child: Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🔙 Custom Back Button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pushReplacementNamed(context, '/home'),
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Live Footage",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Manage cameras',
                            onPressed: () {
                              Navigator.pushNamed(context, '/devices_info');
                            },
                            icon: Icon(
                              Icons.settings_input_antenna,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add camera',
                            onPressed: () {
                              Navigator.pushNamed(context, '/add_device');
                            },
                            icon: Icon(
                              Icons.add_circle,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          IconButton(
                            tooltip: 'How this page works',
                            onPressed: _showLiveGuideDialog,
                            icon: Icon(
                              Icons.info_outline,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
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

      // 🔽 Bottom Navigation Bar
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: widget.devices,
      ),
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
        final displayName = _displayNameFor(cameraId);
        return _CameraPreviewCard(
          cameraId: cameraId,
          displayName: displayName,
          onTap: () => _showLoadingDialog(cameraId, displayName),
          onRename: () => _renameCameraDisplayName(cameraId),
        );
      },
    );
  }
}

// 📹 Camera Preview Card with Live Feed
class _CameraPreviewCard extends StatefulWidget {
  final String cameraId;
  final String displayName;
  final VoidCallback onTap;
  final VoidCallback onRename;

  const _CameraPreviewCard({
    required this.cameraId,
    required this.displayName,
    required this.onTap,
    required this.onRename,
  });

  @override
  State<_CameraPreviewCard> createState() => _CameraPreviewCardState();
}

class _CameraPreviewCardState extends State<_CameraPreviewCard> {
  late final WebViewController _webViewController;
  bool _videoLoaded = false;
  bool _thermalAvailable = false;
  StreamSubscription<DatabaseEvent>? _videoSub;
  StreamSubscription<DatabaseEvent>? _thermalSub;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _loadVideoFeed();
    _listenThermalFeed();
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

    _videoSub = ref.onValue.listen((event) {
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

  void _listenThermalFeed() {
    final ref = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/thermalfeed");

    _thermalSub = ref.onValue.listen((event) {
      final url = (event.snapshot.value as String?)?.trim();
      final available = url != null && url.isNotEmpty;

      if (mounted && available != _thermalAvailable) {
        setState(() {
          _thermalAvailable = available;
        });
      }
    });
  }

  @override
  void dispose() {
    _videoSub?.cancel();
    _thermalSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

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
                          color: primary,
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
                          widget.displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.cameraId,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.wifi,
                              size: 14,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'Connected',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.thermostat,
                              size: 14,
                              color: _thermalAvailable
                                  ? Colors.deepOrange
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _thermalAvailable ? 'Thermal ON' : 'Thermal OFF',
                              style: TextStyle(
                                fontSize: 12,
                                color: _thermalAvailable
                                    ? Colors.deepOrange
                                    : Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Rename display name',
                        onPressed: widget.onRename,
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ],
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
