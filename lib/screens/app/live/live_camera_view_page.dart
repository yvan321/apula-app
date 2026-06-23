import 'dart:async';
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

  bool _videoLoaded = false;
  bool _thermalLoaded = false;

  late final WebViewController _controller;

  StreamSubscription<DatabaseEvent>? _cctvSub;
  StreamSubscription<DatabaseEvent>? _thermalSub;

  String? _lastLoadedUrl;
  String? _lastLoadedView;

  @override
  void initState() {
    super.initState();
    _initWebView();
    _listenToCloudflare();
  }

  void _initWebView() {
    final params = PlatformWebViewControllerCreationParams();

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint("🌐 Page started: $url");
            if (!mounted) return;
            setState(() {
              loading = true;
            });
          },
          onPageFinished: (url) {
            debugPrint("✅ Page finished: $url");
            if (!mounted) return;
            setState(() {
              loading = false;
            });
          },
          onWebResourceError: (error) {
            debugPrint(
              "⚠️ WebView resource error: "
              "type=${error.errorType}, "
              "code=${error.errorCode}, "
              "desc=${error.description}, "
              "url=${error.url}",
            );
          },
        ),
      );

    if (Platform.isAndroid) {
      final androidController =
          _controller.platform as AndroidWebViewController;

      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setMixedContentMode(MixedContentMode.alwaysAllow);
    }
  }

  void _listenToCloudflare() {
    final cctvRef = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("cloudflare/${widget.cameraId}/video_feed");

    final thermalRef = FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
        .ref("thermal_cam/${widget.cameraId}/latest/thermalfeed");

    debugPrint("🔍 Listening to CCTV: cloudflare/${widget.cameraId}/video_feed");
    debugPrint(
      "🔍 Listening to THERMAL: thermal_cam/${widget.cameraId}/latest/thermalfeed",
    );

    _cctvSub = cctvRef.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      debugPrint("📡 Received CCTV URL: $url");

      if (!mounted) return;

      final changed = videoFeedUrl != url;

      setState(() {
        videoFeedUrl = url;
        _videoLoaded = url != null && url.isNotEmpty;
      });

      if (selectedView == "CCTV" && _videoLoaded && changed) {
        _loadSelectedFeed(forceReload: true);
      } else if (selectedView == "CCTV" && !_videoLoaded) {
        setState(() {
          loading = false;
        });
      }
    });

    _thermalSub = thermalRef.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      debugPrint("🔥 Received Thermal URL: $url");

      if (!mounted) return;

      final changed = thermalFeedUrl != url;

      setState(() {
        thermalFeedUrl = url;
        _thermalLoaded = url != null && url.isNotEmpty;
      });

      if (selectedView == "THERMAL" && _thermalLoaded && changed) {
        _loadSelectedFeed(forceReload: true);
      } else if (selectedView == "THERMAL" && !_thermalLoaded) {
        setState(() {
          loading = false;
        });
      }
    });
  }

  String? _currentSelectedUrl() {
    if (selectedView == "CCTV") {
      return videoFeedUrl;
    }
    return thermalFeedUrl;
  }

  void _switchView(String view) {
    if (selectedView == view) return;

    setState(() {
      selectedView = view;
      loading = true;
      _lastLoadedUrl = null;
      _lastLoadedView = null;
    });

    _loadSelectedFeed(forceReload: true);
  }

  void _manualRefresh() {
    setState(() {
      loading = true;
      _lastLoadedUrl = null;
      _lastLoadedView = null;
    });
    _loadSelectedFeed(forceReload: true);
  }

  String _buildHtml(String url, String altLabel) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: black;
      width: 100%;
      height: 100%;
      overflow: hidden;
    }

    .wrap {
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      background: black;
    }

    img {
      width: 100%;
      height: 100%;
      object-fit: contain;
      background: black;
    }
  </style>
</head>
<body>
  <div class="wrap">
    <img id="stream" alt="$altLabel" />
  </div>

  <script>
    const baseUrl = "$url";
    const img = document.getElementById("stream");
    let reconnectAttempts = 0;
    const maxReconnectAttempts = 5;

    function startStream(resetAttempts = false) {
      // Stream MJPEG directly from source URL.
      img.src = baseUrl;
      if (resetAttempts) {
        reconnectAttempts = 0;
      }
      console.log("MJPEG stream started: " + baseUrl);
    }

    img.onerror = function() {
      console.log("Stream error, attempting reconnect...");
      reconnectAttempts++;

      if (reconnectAttempts < maxReconnectAttempts) {
        setTimeout(() => {
          startStream();
        }, 2000);
      } else {
        console.log("Max reconnect attempts reached");
      }
    };

    img.onload = function() {
      console.log("Stream connected");
      reconnectAttempts = 0;
    };

    // Start stream immediately.
    startStream(true);

    setInterval(() => {
      if (!img.src || img.src === "") {
        console.log("Stream appears dead, restarting...");
        startStream(true);
      }
    }, 30000);
  </script>
</body>
</html>
''';
  }

  void _loadSelectedFeed({bool forceReload = false}) {
    final url = _currentSelectedUrl();

    debugPrint("🎥 selectedView=$selectedView");
    debugPrint("🎥 loading url=$url");
    debugPrint("🎥 forceReload=$forceReload");

    if (url == null || url.isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
      return;
    }

    final sameView = _lastLoadedView == selectedView;
    final sameUrl = _lastLoadedUrl == url;

    if (!forceReload && sameView && sameUrl) {
      if (!mounted) return;
      setState(() {
        loading = false;
      });
      return;
    }

    final altLabel = selectedView == "CCTV" ? "CCTV Feed" : "Thermal Feed";
    final html = _buildHtml(url, altLabel);

    _lastLoadedUrl = url;
    _lastLoadedView = selectedView;

    _controller.loadHtmlString(html);
  }

  Widget _buildWaitingView({
    required String message,
    bool showFallbackImage = false,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showFallbackImage)
          Image.asset(
            "assets/examples/thermal_example.png",
            fit: BoxFit.cover,
          )
        else
          Container(color: Colors.black),
        Container(
          color: Colors.black.withOpacity(0.45),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveView() {
    final hasUrl = selectedView == "CCTV"
        ? (videoFeedUrl != null && videoFeedUrl!.isNotEmpty)
        : (thermalFeedUrl != null && thermalFeedUrl!.isNotEmpty);

    if (!hasUrl) {
      return _buildWaitingView(
        message: selectedView == "CCTV"
            ? "Waiting for CCTV feed URL..."
            : "Waiting for thermal feed URL...",
        showFallbackImage: selectedView == "THERMAL",
      );
    }

    return SizedBox.expand(
      child: WebViewWidget(controller: _controller),
    );
  }

  @override
  void dispose() {
    _cctvSub?.cancel();
    _thermalSub?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final pageBackground = isDark ? Colors.black : const Color(0xFFE4DED3);
    final panelBackground = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0EBE2);
    final panelBorder = isDark ? Colors.white12 : Colors.black12;
    final selectedCctvColor = isDark
      ? const Color(0xFF2A2A2A)
      : primary.withOpacity(0.14);
    final selectedThermalColor = isDark
      ? primary.withOpacity(0.28)
      : primary.withOpacity(0.24);
    final inactiveText = isDark ? Colors.white70 : Colors.black54;
    final loadingOverlay = isDark ? Colors.black54 : Colors.black26;

    final hasSelectedUrl = selectedView == "CCTV"
        ? (videoFeedUrl != null && videoFeedUrl!.isNotEmpty)
        : (thermalFeedUrl != null && thermalFeedUrl!.isNotEmpty);

    if (hasSelectedUrl &&
        (_lastLoadedView != selectedView ||
            _lastLoadedUrl != _currentSelectedUrl())) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadSelectedFeed(forceReload: true);
        }
      });
    }

    return Scaffold(
      backgroundColor: pageBackground,
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
                      child: Icon(
                        Icons.chevron_left,
                        size: 32,
                        color: onSurface,
                      ),
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
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
                      ),
                    if (!isFullscreen) const SizedBox(height: 16),

                    if (!isFullscreen)
                      Container(
                        decoration: BoxDecoration(
                          color: panelBackground,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: panelBorder),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _switchView("CCTV"),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: selectedView == "CCTV"
                                        ? selectedCctvColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "CCTV",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: selectedView == "CCTV"
                                          ? (isDark ? Colors.white : onSurface)
                                          : inactiveText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _switchView("THERMAL"),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  decoration: BoxDecoration(
                                    color: selectedView == "THERMAL"
                                        ? selectedThermalColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    "THERMAL",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: selectedView == "THERMAL"
                                          ? primary
                                          : inactiveText,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (!isFullscreen) const SizedBox(height: 20),

                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              color: Colors.black,
                              child: _buildActiveView(),
                            ),
                          ),

                          if (loading)
                            Positioned.fill(
                              child: ColoredBox(
                                color: loadingOverlay,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),

                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: _manualRefresh,
                                  icon: const Icon(
                                    Icons.refresh,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      isFullscreen = !isFullscreen;
                                    });

                                    if (isFullscreen) {
                                      SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.immersiveSticky,
                                      );
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.landscapeLeft,
                                        DeviceOrientation.landscapeRight,
                                      ]);
                                    } else {
                                      SystemChrome.setEnabledSystemUIMode(
                                        SystemUiMode.edgeToEdge,
                                      );
                                      SystemChrome.setPreferredOrientations([
                                        DeviceOrientation.portraitUp,
                                      ]);
                                    }
                                  },
                                  icon: Icon(
                                    isFullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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