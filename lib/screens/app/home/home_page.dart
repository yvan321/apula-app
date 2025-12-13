// home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

// app imports — adjust paths if needed
import 'package:apula/main.dart'; // provides yoloFirebaseApp
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:apula/screens/app/live/livefootage_page.dart';
import 'package:apula/screens/demo/fire_demo_page.dart';
import 'package:apula/services/cnn_listener_service.dart'; // update path if necessary
import 'package:apula/services/global_alert_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

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

  // cnn history
  final List<double> severityHistory = [];
  final List<double> alertHistory = [];

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

  // available devices (kept from your original)
  final List<String> _availableDevices = ["CCTV1", "CCTV2"];

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
  
    _startDatabaseListeners();
    _startCnnListener();
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
    CnnListenerService.startListening((alert, severity, snapshotUrl) {
      setState(() {
        // append history
        severityHistory.add(severity);
        alertHistory.add(alert);
        if (severityHistory.length > 50) severityHistory.removeAt(0);
        if (alertHistory.length > 50) alertHistory.removeAt(0);

        // update last snapshot if provided
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

  Color severityColor(double v) {
    if (v < THRESH_PRE_FIRE) return Colors.green;
    if (v < THRESH_SMOLDERING) return Colors.yellow.shade700;
    if (v < THRESH_IGNITION) return Colors.orange;
    if (v < THRESH_DEVELOPING) return Colors.deepOrange;
    return Colors.red.shade900;
  }

  // ---------- FLChart: Severity ----------
  Widget buildSeverityChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < severityHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), severityHistory[i].clamp(0.0, 1.0)));
    }

    final latest = severityHistory.isEmpty ? 0.0 : severityHistory.last;
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
          maxX: (severityHistory.length <= 1) ? 5 : severityHistory.length.toDouble() - 1,
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

  // ---------- FLChart: Alert ----------
  Widget buildAlertChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < alertHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), alertHistory[i].clamp(0.0, 1.0)));
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
          maxX: (alertHistory.length <= 1) ? 5 : alertHistory.length.toDouble() - 1,
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

                // MINI CNN SUMMARY BOX (Option 1)
                _buildMiniCnnBox(),

                const SizedBox(height: 16),

                // Graphs (Severity, Alert)
                const Text("Fire Prediction (Severity)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                buildSeverityChart(),

                const SizedBox(height: 24),

                const Text("Alert Prediction", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                buildAlertChart(),

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

  // ---------- Mini CNN Summary Box (Option 1) ----------
  Widget _buildMiniCnnBox() {
    final latestSeverity = severityHistory.isEmpty ? 0.0 : severityHistory.last;
    final latestAlert = alertHistory.isEmpty ? 0.0 : alertHistory.last;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          const Text("🔎 LIVE CNN OUTPUT", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("Severity: ${latestSeverity.toStringAsFixed(3)}\nAlert: ${latestAlert.toStringAsFixed(3)}", style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _miniBar("Severity", severityHistory, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _miniBar("Alert", alertHistory, Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBar(String label, List<double> values, Color color) {
    return Container(
      height: 60,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((v) {
          double h = (v.clamp(0, 1)) * 50;
          return Expanded(
            child: Container(height: h, margin: const EdgeInsets.symmetric(horizontal: 1), color: color),
          );
        }).toList(),
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
