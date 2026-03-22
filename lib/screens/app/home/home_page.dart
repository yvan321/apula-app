// home_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

// app imports — adjust paths if needed
import 'package:apula/main.dart'; // provides yoloFirebaseApp
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:apula/screens/app/live/livefootage_page.dart';
import 'package:apula/services/cnn_listener_service.dart';
import 'package:apula/services/global_alert_handler.dart';
import 'package:apula/utils/sensor_pairing_helper.dart';
import 'package:apula/utils/app_palette.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum ChartRange { day, week, month, year }
enum WeatherVisual { sunny, cloudy, rainy }

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;

  String _time = '';
  String _date = '';
  bool _isDay = true;
  Timer? _timer;
  late final AnimationController _skyAnimController;

  int _roomTemp = 28;
  int _fireDetected = 0;
  int _smokeDetected = 0;
  String _lastSnapshotUrl = '';

  final Map<String, List<double>> severityHistoryPerCamera = {};
  final Map<String, List<double>> alertHistoryPerCamera = {};
  final Map<String, List<DateTime>> historyTimestampsPerCamera = {};
  final Map<String, String> sensorStatusPerCamera = {};

  ChartRange _selectedChartRange = ChartRange.day;

  final PageController _chartPageController = PageController();
  int _currentChartPage = 0;

  final List<Map<String, String>> recentActivities = [];

  StreamSubscription<DatabaseEvent>? _sensorSub;

  static const double THRESH_PRE_FIRE = 0.20;
  static const double THRESH_SMOLDERING = 0.40;
  static const double THRESH_IGNITION = 0.60;
  static const double THRESH_DEVELOPING = 0.80;

  static const Duration historySampleInterval = Duration(minutes: 5);
  static const int historyLookbackDays = 30;
  static const int historyMaxPoints = 10000;
  final Map<String, DateTime> _lastHistoryWritePerCamera = {};

  List<String> _availableDevices = [];

  final List<String> _titles = [
    'APULA',
    'Live Footage',
    'Notifications',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _skyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    _loadDevices();
    _loadRecentActivitiesFromFirestore();
    _startDatabaseListeners();
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

            for (final cameraId in _availableDevices) {
              severityHistoryPerCamera[cameraId] = [];
              alertHistoryPerCamera[cameraId] = [];
              historyTimestampsPerCamera[cameraId] = [];
              sensorStatusPerCamera[cameraId] = 'Checking...';
            }
          });

          for (final cameraId in _availableDevices) {
            _loadSensorStatus(cameraId);
          }

          await Future.wait(_availableDevices.map(_loadHistoryForCamera));

          _startCnnListener();
        }
      }
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }
  }

  Future<void> _loadSensorStatus(String cameraId) async {
    final status = await SensorPairingHelper.getSensorStatus(cameraId);
    if (!mounted) return;

    setState(() {
      sensorStatusPerCamera[cameraId] = status;
    });
  }

  Future<void> _loadRecentActivitiesFromFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final email = user.email;
      if (email == null) return;

      // Load last 10 alerts from Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('user_alerts')
          .where('userEmail', isEqualTo: email)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      if (!mounted) return;

      setState(() {
        recentActivities.clear();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final timestamp = data['timestamp'] as Timestamp?;
          final timeAgo = timestamp != null
              ? _formatTimeAgo(timestamp.toDate())
              : 'Unknown time';

          recentActivities.add({
            'title': data['deviceName'] ?? data['device'] ?? 'Fire Alert',
            'time': timeAgo,
            'image': data['snapshotUrl'] ?? '',
          });
        }
      });
    } catch (e) {
      debugPrint('Error loading recent activities: $e');
    }
  }

  String _formatTimeAgo(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${(diff.inDays / 7).floor()}w ago';
    }
  }

  void _updateTime() {
    final now = DateTime.now();
    if (!mounted) return;

    setState(() {
      _time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      _date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _isDay = now.hour >= 6 && now.hour < 18;
    });
  }

  void _startDatabaseListeners() {
    final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);

    _sensorSub = rtdb.ref('sensor_data').onValue.listen((event) {
      final root = event.snapshot.value;
      Map<String, dynamic> sensorMap = {};

      if (root is Map) {
        final preferredCameraId =
            _availableDevices.isNotEmpty ? _availableDevices.first : 'cam_01';

        final preferredNode = root[preferredCameraId];
        if (preferredNode is Map && preferredNode['latest'] is Map) {
          sensorMap = Map<String, dynamic>.from(preferredNode['latest'] as Map);
        } else if (root['latest'] is Map) {
          sensorMap = Map<String, dynamic>.from(root['latest'] as Map);
        }
      }

      final temp = _toInt(sensorMap['DHT_Temp']);
      if (!mounted) return;

      setState(() {
        _roomTemp = temp;
      });
    });
  }

  void _startCnnListener() {
    if (_availableDevices.isEmpty) return;

    CnnListenerService.startListening(
      _availableDevices,
      (cameraId, alert, severity, snapshotUrl, dominantSource) {
        _persistHistoryIfNeeded(cameraId, alert, severity, snapshotUrl);

        GlobalAlertHandler.showFireModal(
          alert: alert,
          severity: severity,
          snapshotUrl: snapshotUrl,
          deviceName: cameraId,
          dominantSource: dominantSource,
        );

        if (!mounted) return;

        setState(() {
          severityHistoryPerCamera.putIfAbsent(cameraId, () => []);
          alertHistoryPerCamera.putIfAbsent(cameraId, () => []);
          historyTimestampsPerCamera.putIfAbsent(cameraId, () => []);

          severityHistoryPerCamera[cameraId]!.add(severity);
          alertHistoryPerCamera[cameraId]!.add(alert);
          historyTimestampsPerCamera[cameraId]!.add(DateTime.now());

          if (severityHistoryPerCamera[cameraId]!.length > historyMaxPoints) {
            severityHistoryPerCamera[cameraId]!.removeAt(0);
          }
          if (alertHistoryPerCamera[cameraId]!.length > historyMaxPoints) {
            alertHistoryPerCamera[cameraId]!.removeAt(0);
          }
          if (historyTimestampsPerCamera[cameraId]!.length > historyMaxPoints) {
            historyTimestampsPerCamera[cameraId]!.removeAt(0);
          }

          if (snapshotUrl.isNotEmpty) {
            _lastSnapshotUrl = snapshotUrl;
          }

          if (severity >= THRESH_DEVELOPING && alert >= 0.80) {
            _fireDetected = 1;
            _smokeDetected = 0;
            _addActivity(
              '$cameraId: Extreme fire danger',
              'just now',
              imageUrl: snapshotUrl,
            );
          } else if (severity >= THRESH_IGNITION && alert >= 0.75) {
            _fireDetected = 1;
            _smokeDetected = 0;
            _addActivity(
              '$cameraId: Ignition anomaly',
              'just now',
              imageUrl: snapshotUrl,
            );
          } else if (severity >= THRESH_SMOLDERING && alert >= 0.73) {
            _fireDetected = 0;
            _smokeDetected = 1;
            _addActivity(
              '$cameraId: Fire-like activity',
              'just now',
              imageUrl: snapshotUrl,
            );
          } else {
            _fireDetected = 0;
            _smokeDetected = 0;
          }
        });
      },
    );
  }

  void _addActivity(String title, String timeAgo, {String imageUrl = ''}) {
    final entry = {
      'title': title,
      'time': timeAgo,
      'image': imageUrl,
    };

    setState(() {
      recentActivities.insert(0, entry);
      if (recentActivities.length > 6) {
        recentActivities.removeLast();
      }
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

  Future<void> _loadHistoryForCamera(String cameraId) async {
    try {
      final cutoff =
          DateTime.now().subtract(const Duration(days: historyLookbackDays));

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

      if (!mounted) return;

      setState(() {
        severityHistoryPerCamera[cameraId] = severity;
        alertHistoryPerCamera[cameraId] = alert;
        historyTimestampsPerCamera[cameraId] = timestamps;
      });
    } catch (e) {
      debugPrint('Error loading history for $cameraId: $e');
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
      debugPrint('Error saving history for $cameraId: $e');
    }
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
      final indexes =
          List<int>.generate(valueLength - start, (i) => start + i);
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

  Color severityColor(double v) {
    if (v < THRESH_PRE_FIRE) return Colors.green;
    if (v < THRESH_SMOLDERING) return Colors.yellow.shade700;
    if (v < THRESH_IGNITION) return Colors.orange;
    if (v < THRESH_DEVELOPING) return Colors.deepOrange;
    return Colors.red.shade900;
  }

  Widget buildSeverityChart(String cameraId) {
    final severityHistory = severityHistoryPerCamera[cameraId] ?? [];
    final filteredIndexes =
        _filteredIndexesForRange(cameraId, severityHistory.length);

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
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: THRESH_PRE_FIRE,
                color: Colors.greenAccent.withOpacity(0.4),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
              HorizontalLine(
                y: THRESH_SMOLDERING,
                color: Colors.yellow.shade700.withOpacity(0.4),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
              HorizontalLine(
                y: THRESH_IGNITION,
                color: Colors.orange.withOpacity(0.4),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
              HorizontalLine(
                y: THRESH_DEVELOPING,
                color: Colors.red.withOpacity(0.25),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
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
                  colors: [
                    lineColor.withOpacity(0.45),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: const FlDotData(show: false),
              isStrokeCapRound: true,
            ),
          ],
          lineTouchData: const LineTouchData(enabled: true),
        ),
      ),
    );
  }

  Widget buildAlertChart(String cameraId) {
    final alertHistory = alertHistoryPerCamera[cameraId] ?? [];
    final filteredIndexes =
        _filteredIndexesForRange(cameraId, alertHistory.length);

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
            bottomTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  colors: [
                    Colors.blue.withOpacity(0.4),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
          lineTouchData: const LineTouchData(enabled: true),
        ),
      ),
    );
  }

  double _daylightFactor(DateTime now) {
    final hourDecimal =
        now.hour + (now.minute / 60.0) + (now.second / 3600.0);

    if (hourDecimal < 6 || hourDecimal >= 18) return 0.0;

    final normalized = (hourDecimal - 6) / 12;
    return math.sin(normalized * math.pi).clamp(0.0, 1.0);
  }

  WeatherVisual _currentWeatherVisual() {
    if (_roomTemp <= 22) return WeatherVisual.rainy;
    if (_roomTemp <= 28) return WeatherVisual.cloudy;
    return WeatherVisual.sunny;
  }

  String _weatherLabel(WeatherVisual condition) {
    switch (condition) {
      case WeatherVisual.sunny:
        return _isDay ? 'Sunny' : 'Clear Night';
      case WeatherVisual.cloudy:
        return _isDay ? 'Cloudy' : 'Cloudy Night';
      case WeatherVisual.rainy:
        return _isDay ? 'Rainy' : 'Rainy Night';
    }
  }

  Widget _buildTimeWeatherCard() {
    final now = DateTime.now();
    final daylight = _daylightFactor(now);
    final condition = _currentWeatherVisual();

    final skyTop =
        Color.lerp(const Color(0xFF0B1120), const Color(0xFF67E8F9), daylight)!;
    final skyBottom =
        Color.lerp(const Color(0xFF1E1B4B), const Color(0xFF0EA5E9), daylight)!;

    final glow =
        Color.lerp(const Color(0xFF1E293B), const Color(0xFF38BDF8), daylight)!;
    final isRainy = condition == WeatherVisual.rainy;
    final isCloudy = condition == WeatherVisual.cloudy;

    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isRainy ? const Color(0xFF475569) : skyTop,
            isRainy ? const Color(0xFF1E293B) : skyBottom,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: glow.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _skyAnimController,
        builder: (context, _) {
          final drift = (_skyAnimController.value * 20) - 10;

          return Stack(
            children: [
              if (isCloudy || isRainy) ...[
                Positioned(
                  top: 10,
                  right: 20 + drift,
                  child: Icon(
                    Icons.cloud,
                    size: 36,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
                Positioned(
                  top: 34,
                  right: 56 + (drift * 0.7),
                  child: Icon(
                    Icons.cloud,
                    size: 26,
                    color: Colors.white.withOpacity(0.40),
                  ),
                ),
              ],
              if (isRainy)
                Positioned(
                  top: 44,
                  right: 20,
                  child: Row(
                    children: List.generate(
                      3,
                      (_) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          Icons.grain,
                          size: 12,
                          color: Colors.white.withOpacity(0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _isDay
                            ? (isCloudy
                                ? Icons.wb_cloudy
                                : (isRainy ? Icons.grain : Icons.wb_sunny))
                            : (isRainy
                                ? Icons.grain
                                : Icons.nightlight_round),
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _time,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _date,
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                  Text(
                    _weatherLabel(condition),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCnnTestModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CNN Test Controls',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.local_fire_department),
                label: const Text('Simulate Fire Alert'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud),
                label: const Text('Simulate Smoke Alert'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('Simulate Normal'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemperatureCard() {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _roomTemp >= 30
              ? [AppPalette.secondaryWarm, AppPalette.primaryFire]
              : [Colors.blue.shade400, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_roomTemp >= 30
                    ? AppPalette.secondaryWarm
                    : Colors.blue)
                .withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              const Icon(Icons.thermostat, color: Colors.white, size: 28),
              const SizedBox(height: 8),
              Text(
                '$_roomTemp°C',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Room Temp',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Buttons row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Increase'),
                onPressed: () {
                  setState(() {
                    _roomTemp = (_roomTemp + 1).clamp(0, 50);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('Decrease'),
                onPressed: () {
                  setState(() {
                    _roomTemp = (_roomTemp - 1).clamp(0, 50);
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.info, size: 16),
                label: const Text('Details'),
                onPressed: _showCnnTestModal,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
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
          'No cameras available',
          style: TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    final safeIndex = _currentChartPage.clamp(0, _availableDevices.length - 1);
    final currentCameraId = _availableDevices[safeIndex];

    final latestSeverity =
        (severityHistoryPerCamera[currentCameraId] ?? []).isEmpty
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
            '🔎 LIVE CNN OUTPUT - ${currentCameraId.toUpperCase()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Severity: ${latestSeverity.toStringAsFixed(3)}\nAlert: ${latestAlert.toStringAsFixed(3)}',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _activityItem(String title, String time, {String imageUrl = ''}) {
    return Card(
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: imageUrl.isNotEmpty
            ? (imageUrl.startsWith('http')
                ? Image.network(
                    imageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  )
                : const Icon(Icons.image, color: Colors.white54))
            : const Icon(Icons.check_circle, color: Colors.green),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(time, style: const TextStyle(color: Colors.white70)),
      ),
    );
  }

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
                    const Icon(
                      Icons.videocam,
                      color: Color(0xFFA30000),
                      size: 24,
                    ),
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
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
          const Text(
            'Fire Prediction (Severity)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          buildSeverityChart(cameraId),
          const SizedBox(height: 20),
          const Text(
            'Alert Prediction',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          buildAlertChart(cameraId),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _skyAnimController.dispose();
    _sensorSub?.cancel();
    _chartPageController.dispose();
    CnnListenerService.stopAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (_fireDetected == 1) {
      statusColor = Colors.red;
      statusIcon = Icons.local_fire_department;
      statusText = 'Fire detected, immediate attention required';
    } else if (_smokeDetected == 1) {
      statusColor = Colors.orange;
      statusIcon = Icons.cloud;
      statusText = 'Smoke detected, possible fire risk';
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'System normal, no fire detected';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        centerTitle: true,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Prevention Starts with Detection',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: Colors.white, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _time,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _date,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _buildTimeWeatherCard()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildTemperatureCard()),
                  ],
                ),
                const SizedBox(height: 20),
                _buildMiniCnnBox(),
                const SizedBox(height: 16),
                if (_availableDevices.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Camera Predictions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    height: 620,
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
                        'No cameras added yet',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Activity',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                ...recentActivities.map(
                  (a) => _activityItem(
                    a['title'] ?? '',
                    a['time'] ?? '',
                    imageUrl: a['image'] ?? '',
                  ),
                ),
                if (recentActivities.isEmpty)
                  const Text(
                    'No recent activity',
                    style: TextStyle(color: Colors.white54),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          LiveFootagePage(devices: _availableDevices),

          const Center(child: Text('Notifications Page 🔔')),

          const Center(child: Text('Settings Page ⚙️')),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: _availableDevices,
      ),
    );
  }
}