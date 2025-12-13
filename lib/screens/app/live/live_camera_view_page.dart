import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

// Conditional MJPEG imports
import 'mjpeg/mobile_mjpeg_view.dart'
    if (dart.library.html) 'mjpeg/web_mjpeg_view.dart';

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

  @override
  void initState() {
    super.initState();
    _listenToCloudflare();
  }

  void _listenToCloudflare() {
    final ref = FirebaseDatabase.instance
        .ref("cloudflare/${widget.cameraId}/video_feed");

    ref.onValue.listen((event) {
      final url = event.snapshot.value as String?;
      if (url != null && mounted) {
        setState(() {
          videoFeedUrl = url;
          loading = false;
        });
      }
    });
  }

  Widget _buildCctvView() {
    if (videoFeedUrl == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return IgnorePointer(
      ignoring: true,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1920,
            height: 1080,
            child: MJpegView(url: videoFeedUrl!),
          ),
        ),
      ),
    );
  }

  Widget _buildThermalView() {
    return Image.asset(
      "assets/examples/thermal_example.png",
      fit: BoxFit.cover,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
