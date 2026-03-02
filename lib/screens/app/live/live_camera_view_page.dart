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
  String? thermalFeedUrl;
  late final WebViewController _webViewController;
  late final WebViewController _thermalWebViewController;
  bool _videoLoaded = false;
  bool _thermalLoaded = false;

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

    _thermalWebViewController =
        WebViewController.fromPlatformCreationParams(params)
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.black);

    // Enable video playback on Android
    if (Platform.isAndroid) {
      final androidController =
          _webViewController.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);

      final thermalAndroidController =
          _thermalWebViewController.platform as AndroidWebViewController;
      thermalAndroidController.setMediaPlaybackRequiresUserGesture(false);
    }
  }

  void _listenToCloudflare() {
    final cctvRef = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/video_feed");

    final thermalRef = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/thermalfeed");

    print('🔍 Listening to: cloudflare/${widget.cameraId}/video_feed');
    print('🔍 Listening to: cloudflare/${widget.cameraId}/thermalfeed');

    cctvRef.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      print('📡 Received CCTV URL: $url');
      
      if (url != null && mounted) {
        print('✅ Loading video in WebView');
        _loadFeedInWebView(url, _webViewController, "CCTV Feed");
        setState(() {
          videoFeedUrl = url;
          _videoLoaded = true;
          if (selectedView == "CCTV") {
            loading = false;
          }
        });
      } else {
        print('⚠️ No video feed URL found');
        if (mounted && selectedView == "CCTV") {
          setState(() {
            loading = false;
          });
        }
      }
    });

    thermalRef.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      print('📡 Received Thermal URL: $url');

      if (url != null && mounted) {
        print('✅ Loading thermal feed in WebView');
        _loadFeedInWebView(url, _thermalWebViewController, "Thermal Feed");
        setState(() {
          thermalFeedUrl = url;
          _thermalLoaded = true;
          if (selectedView == "THERMAL") {
            loading = false;
          }
        });
      } else {
        print('⚠️ No thermal feed URL found');
        if (mounted && selectedView == "THERMAL") {
          setState(() {
            loading = false;
          });
        }
      }
    });
  }

  void _loadFeedInWebView(
    String url,
    WebViewController controller,
    String altLabel,
  ) {
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
        <img src="$url" alt="$altLabel" />
      </body>
      </html>
    ''';

    controller.loadHtmlString(html);
  }

  Widget _buildCctvView() {
    return SizedBox.expand(
      child: WebViewWidget(controller: _webViewController),
    );
  }

  Widget _buildThermalView() {
    if (_thermalLoaded) {
      return SizedBox.expand(
        child: WebViewWidget(controller: _thermalWebViewController),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          "assets/examples/thermal_example.png",
          fit: BoxFit.cover,
        ),
        Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.center,
          child: const Text(
            "Waiting for thermalfeed URL...",
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
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
                            loading = selectedView == "CCTV"
                                ? !_videoLoaded
                                : !_thermalLoaded;
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
