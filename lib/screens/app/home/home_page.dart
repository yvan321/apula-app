// home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

// app imports — adjust paths if needed
import 'package:apula/main.dart'; // provides yoloFirebaseApp
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:apula/screens/app/live/livefootage_page.dart';
import 'package:apula/screens/demo/fire_demo_page.dart';
import 'package:apula/services/cnn_listener_service.dart'; // update path if necessary
import 'package:apula/services/global_alert_handler.dart';
import 'package:apula/utils/sensor_pairing_helper.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum ChartRange { day, week, month, year }

class _HomePageState extends State<HomePage> {
  // navigation
  int _selectedIndex = 0;

  // clock + day/night
  String _time = "", _date = "";
  bool _isDay = true;
  Timer? _timer;

  // realtime sensor & status
  int _roomTemp = 28;
  int _fireDetected = 0;
  int _smokeDetected = 0;
  String _lastSnapshotUrl = "";

  // PER-CAMERA CNN history
  final Map<String, List<double>> severityHistoryPerCamera = {};
  final Map<String, List<double>> alertHistoryPerCamera = {};
  final Map<String, List<DateTime>> historyTimestampsPerCamera = {};
  final Map<String, String> sensorStatusPerCamera = {};

  ChartRange _selectedChartRange = ChartRange.day;

  // PageView controller for swipeable charts
  final PageController _chartPageController = PageController();
  int _currentChartPage = 0;

  // activity feed
  final List<Map<String, String>> recentActivities = [];

  // DB subscriptions
  StreamSubscription<DatabaseEvent>? _sensorSub;
  StreamSubscription<DatabaseEvent>? _camLatestSub;
  StreamSubscription<DatabaseEvent>? _camChildAddedSub;

  // thresholds
  static const double THRESH_PRE_FIRE = 0.20;
  static const double THRESH_SMOLDERING = 0.40;
  static const double THRESH_IGNITION = 0.60;
  static const double THRESH_DEVELOPING = 0.80;

  // history persistence (Firestore)
  static const Duration historySampleInterval = Duration(minutes: 5);
  static const int historyLookbackDays = 30;
  static const int historyMaxPoints = 10000;
  final Map<String, DateTime> _lastHistoryWritePerCamera = {};

  // available devices - loaded from Firestore
  List<String> _availableDevices = [];

  // Titles
  final List<String> _titles = [
    "APULA",
    "Live Footage",
    "Notifications",
    "Settings",
  ];

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _loadDevices();
    _startDatabaseListeners();
    // CNN listener started after devices are loaded
  }

  Future<void> _loadDevices() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final userData = query.docs.first.data();
        final List<dynamic>? cameraIds = userData['cameraIds'];
        
        if (cameraIds != null && mounted) {
          setState(() {
            _availableDevices = List<String>.from(cameraIds);
            
            // Initialize history for each camera
            for (final cameraId in _availableDevices) {
              severityHistoryPerCamera[cameraId] = [];
              alertHistoryPerCamera[cameraId] = [];
              historyTimestampsPerCamera[cameraId] = [];
              sensorStatusPerCamera[cameraId] = 'Checking...';
            }
          });
          
          // Load sensor status for each camera
          for (final cameraId in _availableDevices) {
            _loadSensorStatus(cameraId);
          }

          // Load long-term history for charts
          await Future.wait(
            _availableDevices.map(_loadHistoryForCamera),
          );
          
          // Start CNN listener for all cameras
          _startCnnListener();
        }
      }
    } catch (e) {
      print('Error loading devices: $e');
    }
  }

  Future<void> _loadSensorStatus(String cameraId) async {
    final status = await SensorPairingHelper.getSensorStatus(cameraId);
    if (mounted) {
      setState(() {
        sensorStatusPerCamera[cameraId] = status;
      });
    }
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      _time =
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      _date =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      _isDay = now.hour >= 6 && now.hour < 18;
    });
  }

  void _startDatabaseListeners() {
    final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);

    // Temperature listener
    _sensorSub = rtdb.ref('sensor_data/latest').onValue.listen((event) {
      final map = (event.snapshot.value ?? {}) as Map;
      final temp = _toInt(map['DHT_Temp']);
      setState(() => _roomTemp = temp);
    });

    // cam_detections latest (status + thumbnail)
    _camLatestSub = rtdb.ref('cam_detections/latest').onValue.listen((event) {
      final map = (event.snapshot.value ?? {}) as Map;
      setState(() {
        _fireDetected = _toInt(map['fire_detected']);
        _smokeDetected = _toInt(map['smoke_detected']);
        _lastSnapshotUrl = (map['image_url'] ?? '') as String;

        // push a small activity when detection occurs
        if (_fireDetected == 1 || _smokeDetected == 1) {
          final label = _fireDetected == 1 ? 'Fire Detected' : 'Smoke Detected';
          _addActivity(label, 'just now', imageUrl: _lastSnapshotUrl);
        }
      });
    });

    // recent activities from cam_detections (last 10)
    final camRef = rtdb.ref('cam_detections');
    _camChildAddedSub = camRef.limitToLast(10).onChildAdded.listen((event) {
      final m = (event.snapshot.value ?? {}) as Map;
      final ts = (m['timestamp'] ?? '').toString();
      final imageUrl = (m['image_url'] ?? '').toString();
      String label = 'Detection logged';
      if ((m['fire_detected'] ?? 0) == 1) label = 'Fire event';
      else if ((m['smoke_detected'] ?? 0) == 1) label = 'Smoke event';

      _addActivity(label, ts, imageUrl: imageUrl);
    });
  }

  void _addActivity(String title, String timeAgo, {String imageUrl = ''}) {
    final entry = {
      'title': title,
      'time': timeAgo,
      'image': imageUrl,
    };
    setState(() {
      recentActivities.insert(0, entry);
      if (recentActivities.length > 6) recentActivities.removeLast();
    });
  }

  void _startCnnListener() {
    if (_availableDevices.isEmpty) return;

    CnnListenerService.startListening(_availableDevices, (cameraId, alert, severity, snapshotUrl) {
      _persistHistoryIfNeeded(cameraId, alert, severity, snapshotUrl);

      // Trigger global fire modal if severity is high
      GlobalAlertHandler.showFireModal(
        alert: alert,
        severity: severity,
        snapshotUrl: snapshotUrl,
        deviceName: cameraId,
      );

      setState(() {
        // Initialize if needed
        severityHistoryPerCamera.putIfAbsent(cameraId, () => []);
        alertHistoryPerCamera.putIfAbsent(cameraId, () => []);
        historyTimestampsPerCamera.putIfAbsent(cameraId, () => []);

        // Append history for this camera
        severityHistoryPerCamera[cameraId]!.add(severity);
        alertHistoryPerCamera[cameraId]!.add(alert);
        historyTimestampsPerCamera[cameraId]!.add(DateTime.now());
        
        // Keep last N points in-memory for smooth charts
        if (severityHistoryPerCamera[cameraId]!.length > historyMaxPoints) {
          severityHistoryPerCamera[cameraId]!.removeAt(0);
        }
        if (alertHistoryPerCamera[cameraId]!.length > historyMaxPoints) {
          alertHistoryPerCamera[cameraId]!.removeAt(0);
        }
        if (historyTimestampsPerCamera[cameraId]!.length > historyMaxPoints) {
          historyTimestampsPerCamera[cameraId]!.removeAt(0);
        }

        // Update last snapshot if provided
        if (snapshotUrl.isNotEmpty) _lastSnapshotUrl = snapshotUrl;
      });
    });
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  List<int> _filteredIndexesForRange(String cameraId, int valueLength) {
    if (valueLength == 0) return const [];

    final timestamps = historyTimestampsPerCamera[cameraId] ?? const [];

    if (timestamps.length != valueLength) {
      final fallbackWindow = switch (_selectedChartRange) {
        ChartRange.day => 288,
        ChartRange.week => 2016,
        ChartRange.month => 8640,
        ChartRange.year => historyMaxPoints,
      };
      final start = (valueLength - fallbackWindow).clamp(0, valueLength);
      final indexes = List<int>.generate(valueLength - start, (i) => start + i);
      return _downsampleIndexes(indexes, 240);
    }

    final now = DateTime.now();
    final cutoff = switch (_selectedChartRange) {
      ChartRange.day => now.subtract(const Duration(days: 1)),
      ChartRange.week => now.subtract(const Duration(days: 7)),
      ChartRange.month => now.subtract(const Duration(days: 30)),
      ChartRange.year => now.subtract(const Duration(days: 365)),
    };

    final indexes = <int>[];
    for (int i = 0; i < valueLength; i++) {
      if (timestamps[i].isAfter(cutoff)) {
        indexes.add(i);
      }
    }

    if (indexes.isEmpty) {
      indexes.add(valueLength - 1);
    }

    return _downsampleIndexes(indexes, 240);
  }

  List<int> _downsampleIndexes(List<int> source, int maxPoints) {
    if (source.length <= maxPoints) return source;

    final sampled = <int>[];
    final step = (source.length - 1) / (maxPoints - 1);

    for (int i = 0; i < maxPoints; i++) {
      final idx = source[(i * step).round().clamp(0, source.length - 1)];
      if (sampled.isEmpty || sampled.last != idx) {
        sampled.add(idx);
      }
    }

    return sampled;
  }

  String _chartRangeLabel(ChartRange range) {
    switch (range) {
      case ChartRange.day:
        return 'Day';
      case ChartRange.week:
        return 'Week';
      case ChartRange.month:
        return 'Month';
      case ChartRange.year:
        return 'Year';
    }
  }

  Future<void> _loadHistoryForCamera(String cameraId) async {
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: historyLookbackDays));
      final snap = await FirebaseFirestore.instance
          .collection('cnn_history')
          .doc(cameraId)
          .collection('points')
          .where('ts', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('ts')
          .get();

      final severity = <double>[];
      final alert = <double>[];
      final timestamps = <DateTime>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        severity.add(_toDouble(data['severity']));
        alert.add(_toDouble(data['alert']));
        final ts = data['ts'];
        if (ts is Timestamp) {
          timestamps.add(ts.toDate());
        } else if (ts is DateTime) {
          timestamps.add(ts);
        } else {
          timestamps.add(DateTime.now());
        }
      }

      if (mounted) {
        setState(() {
          severityHistoryPerCamera[cameraId] = severity;
          alertHistoryPerCamera[cameraId] = alert;
          historyTimestampsPerCamera[cameraId] = timestamps;
        });
      }
    } catch (e) {
      print('Error loading history for $cameraId: $e');
    }
  }

  Future<void> _persistHistoryIfNeeded(
    String cameraId,
    double alert,
    double severity,
    String snapshotUrl,
  ) async {
    final now = DateTime.now();
    final last = _lastHistoryWritePerCamera[cameraId];
    if (last != null && now.difference(last) < historySampleInterval) {
      return;
    }

    _lastHistoryWritePerCamera[cameraId] = now;

    try {
      await FirebaseFirestore.instance
          .collection('cnn_history')
          .doc(cameraId)
          .collection('points')
          .add({
        'alert': alert,
        'severity': severity,
        'snapshotUrl': snapshotUrl,
        'ts': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving history for $cameraId: $e');
    }
  }

  Color severityColor(double v) {
    if (v < THRESH_PRE_FIRE) return Colors.green;
    if (v < THRESH_SMOLDERING) return Colors.yellow.shade700;
    if (v < THRESH_IGNITION) return Colors.orange;
    if (v < THRESH_DEVELOPING) return Colors.deepOrange;
    return Colors.red.shade900;
  }

  // ---------- FLChart: Severity (per camera) ----------
  Widget buildSeverityChart(String cameraId) {
    final severityHistory = severityHistoryPerCamera[cameraId] ?? [];
    final filteredIndexes = _filteredIndexesForRange(cameraId, severityHistory.length);
    
    final spots = <FlSpot>[];
    for (int i = 0; i < filteredIndexes.length; i++) {
      final value = severityHistory[filteredIndexes[i]].clamp(0.0, 1.0);
      spots.add(FlSpot(i.toDouble(), value));
    }

    final latest = spots.isEmpty ? 0.0 : spots.last.y;
    final lineColor = severityColor(latest);

    return Container(
      padding: const EdgeInsets.all(12),
      height: 260,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          // x range
          minX: 0,
          maxX: (spots.length <= 1) ? 5 : spots.length.toDouble() - 1,
          minY: 0,
          maxY: 1,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 0.2,
            verticalInterval: 5,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.2,
                getTitlesWidget: (v, meta) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                ),
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(y: THRESH_PRE_FIRE, color: Colors.greenAccent.withOpacity(0.4), strokeWidth: 1, dashArray: [4, 4]),
            HorizontalLine(y: THRESH_SMOLDERING, color: Colors.yellow.shade700.withOpacity(0.4), strokeWidth: 1, dashArray: [4, 4]),
            HorizontalLine(y: THRESH_IGNITION, color: Colors.orange.withOpacity(0.4), strokeWidth: 1, dashArray: [4, 4]),
            HorizontalLine(y: THRESH_DEVELOPING, color: Colors.red.withOpacity(0.25), strokeWidth: 1, dashArray: [4, 4]),
          ]),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              barWidth: 3,
              color: lineColor,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [lineColor.withOpacity(0.45), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: FlDotData(show: false),
              isStrokeCapRound: true,
            ),
          ],
          lineTouchData: LineTouchData(enabled: true),
        ),
      ),
    );
  }

  // ---------- FLChart: Alert (per camera) ----------
  Widget buildAlertChart(String cameraId) {
    final alertHistory = alertHistoryPerCamera[cameraId] ?? [];
    final filteredIndexes = _filteredIndexesForRange(cameraId, alertHistory.length);
    
    final spots = <FlSpot>[];
    for (int i = 0; i < filteredIndexes.length; i++) {
      final value = alertHistory[filteredIndexes[i]].clamp(0.0, 1.0);
      spots.add(FlSpot(i.toDouble(), value));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length <= 1) ? 5 : spots.length.toDouble() - 1,
          minY: 0,
          maxY: 1,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: 0.2,
            verticalInterval: 5,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
            getDrawingVerticalLine: (value) =>
                FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 0.2,
                getTitlesWidget: (v, meta) =>
                    Text(v.toStringAsFixed(1), style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              barWidth: 3,
              color: Colors.blueAccent,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [Colors.blue.withOpacity(0.4), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: FlDotData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(enabled: true),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sensorSub?.cancel();
    _camLatestSub?.cancel();
    _camChildAddedSub?.cancel();
    _chartPageController.dispose();
    CnnListenerService.stopAll();
    super.dispose();
  }

  // ---------- build UI ----------
  @override
  Widget build(BuildContext context) {
    final statusText = _fireDetected == 1
        ? "🔥 FIRE DETECTED"
        : _smokeDetected == 1
            ? "⚠️ SMOKE DETECTED"
            : "System Active\nNo Fire Detected";

    final statusIcon = _fireDetected == 1
        ? Icons.local_fire_department
        : _smokeDetected == 1
            ? Icons.cloud
            : Icons.check_circle;

    final statusColor = _fireDetected == 1
        ? Colors.red.shade700
        : _smokeDetected == 1
            ? Colors.orange
            : Colors.green;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: _selectedIndex == 0
            ? Row(children: [Image.asset("assets/logo.png", height: 40)])
            : Row(
                children: [
                  Image.asset("assets/apula_home_icon.png", height: 35),
                  const SizedBox(width: 8),
                  Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // ------------ HOME (index 0) ------------
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Prevention Starts with Detection", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Status Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: statusColor.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))],
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: Colors.white, size: 40),
                      const SizedBox(width: 12),
                      Expanded(child: Text(statusText, style: const TextStyle(color: Colors.white, fontSize: 16))),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [Text(_time, style: const TextStyle(color: Colors.white70)), const SizedBox(height: 4), Text(_date, style: const TextStyle(color: Colors.white70))],
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Time & Temperature Row
                Row(children: [Expanded(child: _buildTimeDateCard()), const SizedBox(width: 12), Expanded(child: _buildTemperatureCard())]),

                const SizedBox(height: 20),

                // MINI CNN SUMMARY BOX
                _buildMiniCnnBox(),

                const SizedBox(height: 16),

                // Swipeable Camera Charts
                if (_availableDevices.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Camera Predictions", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      // Page indicators
                      Row(
                        children: List.generate(
                          _availableDevices.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentChartPage == index
                                  ? const Color(0xFFA30000)
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 620, // height for both charts + spacing + camera info
                    child: PageView.builder(
                      controller: _chartPageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentChartPage = index;
                        });
                      },
                      itemCount: _availableDevices.length,
                      itemBuilder: (context, index) {
                        final cameraId = _availableDevices[index];
                        return _buildCameraChartPage(cameraId);
                      },
                    ),
                  ),
                ] else
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        "No cameras added yet",
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Recent Activity
                const Text("Recent Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ...recentActivities.map((a) => _activityItem(a['title']!, a['time']!, imageUrl: a['image']!)).toList(),
                if (recentActivities.isEmpty) const Text("No recent activity", style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 40),
              ],
            ),
          ),

          // ------------ LIVE FOOTAGE (index 1) ------------
          const Center(child: Text("Live Footage Page")), // replace with your actual LiveFootagePage if desired
          // you had LiveFootagePage in imports earlier; to show it uncomment below and pass devices:
          // LiveFootagePage(devices: _availableDevices),

          // ------------ NOTIFICATIONS (index 2) ------------
          const Center(child: Text("Notifications Page 🔔")),

          // ------------ SETTINGS (index 3) ------------
          const Center(child: Text("Settings Page ⚙️")),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(selectedIndex: _selectedIndex, onItemTapped: _onItemTapped, availableDevices: _availableDevices),
    );
  }

  // ---------- Camera Chart Page ----------
  Widget _buildCameraChartPage(String cameraId) {
    final sensorStatus = sensorStatusPerCamera[cameraId] ?? 'Checking...';
    final latestSeverity = (severityHistoryPerCamera[cameraId] ?? []).isEmpty
        ? 0.0
        : severityHistoryPerCamera[cameraId]!.last;
    final latestAlert = (alertHistoryPerCamera[cameraId] ?? []).isEmpty
        ? 0.0
        : alertHistoryPerCamera[cameraId]!.last;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Camera Info Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFA30000), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.videocam, color: Color(0xFFA30000), size: 24),
                    const SizedBox(width: 8),
                    Text(
                      cameraId.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.sensors, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sensorStatus,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricTag('Severity', latestSeverity),
                    _buildMetricTag('Alert', latestAlert),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ChartRange.values.map((range) {
              final selected = _selectedChartRange == range;
              return ChoiceChip(
                label: Text(_chartRangeLabel(range)),
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _selectedChartRange = range;
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // Severity Chart
          const Text(
            "Fire Prediction (Severity)",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          buildSeverityChart(cameraId),

          const SizedBox(height: 20),

          // Alert Chart
          const Text(
            "Alert Prediction",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          buildAlertChart(cameraId),
        ],
      ),
    );
  }

  Widget _buildMetricTag(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(3),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ---------- Mini CNN Summary Box ----------
  Widget _buildMiniCnnBox() {
    if (_availableDevices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          "No cameras available",
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Show data for currently viewed camera
    final currentCameraId = _availableDevices[_currentChartPage];
    final latestSeverity = (severityHistoryPerCamera[currentCameraId] ?? []).isEmpty
        ? 0.0
        : severityHistoryPerCamera[currentCameraId]!.last;
    final latestAlert = (alertHistoryPerCamera[currentCameraId] ?? []).isEmpty
        ? 0.0
        : alertHistoryPerCamera[currentCameraId]!.last;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            "🔎 LIVE CNN OUTPUT - ${currentCameraId.toUpperCase()}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Severity: ${latestSeverity.toStringAsFixed(3)}\nAlert: ${latestAlert.toStringAsFixed(3)}",
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // ---------- time card + temp card helpers ----------
  Widget _buildTimeDateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _isDay ? [Colors.blue.shade400, Colors.blue.shade700] : [Colors.indigo.shade400, Colors.indigo.shade900], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _isDay ? Colors.blue.withOpacity(0.4) : Colors.indigo.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_isDay ? Icons.wb_sunny : Icons.nightlight_round, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text(_time, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text(_date, style: const TextStyle(fontSize: 14, color: Colors.white70)),
      ]),
    );
  }

  Widget _buildTemperatureCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _roomTemp >= 30 ? [Colors.red.shade400, Colors.red.shade700] : [Colors.blue.shade400, Colors.blue.shade700], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: _roomTemp >= 30 ? Colors.red.withOpacity(0.4) : Colors.blue.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        const Icon(Icons.thermostat, color: Colors.white, size: 28),
        const SizedBox(height: 8),
        Text("$_roomTemp°C", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        const Text("Room Temp", style: TextStyle(fontSize: 14, color: Colors.white70)),
      ]),
    );
  }

  Widget _activityItem(String title, String time, {String imageUrl = ''}) {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: imageUrl.isNotEmpty ? (imageUrl.startsWith("http") ? Image.network(imageUrl, width: 56, height: 56, fit: BoxFit.cover) : Icon(Icons.image, color: Colors.white54)) : Icon(Icons.check_circle, color: Colors.green),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(time, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

  // navigation handler
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }
}
