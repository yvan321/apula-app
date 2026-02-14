import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../../main.dart';

class LiveCameraViewPage extends StatefulWidget {
  final String deviceName;
  final String cameraId;

  const LiveCameraViewPage({
    super.key,
    required this.deviceName,
    required this.cameraId,
  });

  @override
  State<LiveCameraViewPage> createState() => _LiveCameraViewPageState();
}

class _LiveCameraViewPageState extends State<LiveCameraViewPage> {
  bool isFullscreen = false;
  bool loading = true;
  String selectedView = "CCTV";

  String? videoFeedUrl;
  late final WebViewController _webViewController;
  bool _videoLoaded = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _listenToCloudflare();
  }

  void _initWebView() {
    final params = PlatformWebViewControllerCreationParams();

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    // Enable video playback on Android
    if (Platform.isAndroid) {
      final androidController =
          _webViewController.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _listenToCloudflare() {
    final ref = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/video_feed");

    print('🔍 Listening to: cloudflare/${widget.cameraId}/video_feed');

    ref.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      print('📡 Received URL: $url');
      
      if (url != null && mounted) {
        print('✅ Loading video in WebView');
        _loadVideoInWebView(url);
        setState(() {
          videoFeedUrl = url;
          _videoLoaded = true;
          loading = false;
        });
      } else {
        print('⚠️ No video feed URL found');
        if (mounted) {
          setState(() {
            loading = false;
          });
        }
      }
    });
  }

  void _loadVideoInWebView(String url) {
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
            object-fit: contain;
          }
        </style>
      </head>
      <body>
        <img src="$url" alt="CCTV Feed" />
      </body>
      </html>
    ''';

    _webViewController.loadHtmlString(html);
  }

  Widget _buildCctvView() {
    return SizedBox.expand(
      child: WebViewWidget(controller: _webViewController),
    );
  }

  Widget _buildThermalView() {
    return Image.asset(
      "assets/examples/thermal_example.png",
      fit: BoxFit.cover,
    );
  }

  @override
  void dispose() {
    // Reset orientation when leaving page
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            if (!isFullscreen)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.chevron_left, size: 32),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isFullscreen ? 0 : 20),
                child: Column(
                  children: [
                    if (!isFullscreen)
                      Text(
                        "Live Footage - ${widget.deviceName}",
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                    if (!isFullscreen) const SizedBox(height: 12),

                    if (!isFullscreen)
                      ToggleButtons(
                        borderRadius: BorderRadius.circular(12),
                        isSelected: [
                          selectedView == "CCTV",
                          selectedView == "THERMAL",
                        ],
                        onPressed: (i) {
                          setState(() {
                            selectedView = i == 0 ? "CCTV" : "THERMAL";
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text("CCTV"),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text("THERMAL"),
                          ),
                        ],
                      ),

                    if (!isFullscreen) const SizedBox(height: 20),

                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: isFullscreen
                              ? BorderRadius.zero
                              : BorderRadius.circular(20),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            selectedView == "CCTV"
                                ? _buildCctvView()
                                : _buildThermalView(),

                            if (loading)
                              const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),

                            Positioned(
                              top: 10,
                              right: 10,
                              child: IconButton(
                                icon: Icon(
                                  isFullscreen
                                      ? Icons.fullscreen_exit
                                      : Icons.fullscreen,
                                  color: Colors.white,
                                  size: 30,
                                ),
                                onPressed: () {
                                  setState(() {
                                    isFullscreen = !isFullscreen;
                                    if (isFullscreen) {
                                      // Enter fullscreen - landscape mode
                                      SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.immersiveSticky,
                                      );
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.landscapeLeft,
                                        DeviceOrientation.landscapeRight,
                                      ]);
                                    } else {
                                      // Exit fullscreen - portrait mode
                                      SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.edgeToEdge,
                                      );
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.portraitUp,
                                      ]);
                                    }
                                  });
                                },
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
          ],
        ),
      ),
    );
  }
}
