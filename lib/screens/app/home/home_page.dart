// home_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

// app imports
import 'package:apula/main.dart'; // provides yoloFirebaseApp
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:apula/widgets/global_manual_alert_button.dart';
import 'package:apula/services/cnn_listener_service.dart';
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

  static List<Map<String, dynamic>> _persistedActivities = [];
  List<Map<String, dynamic>> recentActivities = [];
  StreamSubscription<DatabaseEvent>? _sensorSub;
  late final CnnCallback _homeCnnCallback;

  static const double THRESH_PRE_FIRE = 0.20;
  static const double THRESH_SMOLDERING = 0.40;
  static const double THRESH_IGNITION = 0.60;
  static const double THRESH_DEVELOPING = 0.80;

  static const Duration historySampleInterval = Duration(minutes: 5);
  static const int historyLookbackDays = 30;
  static const int historyMaxPoints = 10000;
  final Map<String, DateTime> _lastHistoryWritePerCamera = {};

  List<String> _availableDevices = [];
  String? _selectedSimulationCameraId;
  String? _mainStatusCameraId;
  bool _guideDialogOpen = false;

  @override
  void initState() {
    super.initState();

    _homeCnnCallback = _handleCnnUpdate;

    _skyAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    _loadDevices();
    _startDatabaseListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowAppGuide();
    });

    recentActivities = List<Map<String, dynamic>>.from(_persistedActivities);
  }

  Future<void> _maybeShowAppGuide() async {
    if (!mounted || _guideDialogOpen) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'app_guide_shown_${user.uid}';
    final shown = prefs.getBool(key) ?? false;
    if (shown) return;

    _guideDialogOpen = true;
    await _showAppGuideModal();
    await prefs.setBool(key, true);
    _guideDialogOpen = false;
  }

  Future<void> _showAppGuideModal() async {
    if (!mounted) return;

    final primary = Theme.of(context).colorScheme.primary;
    final pages = <Map<String, String>>[
      {
        'title': 'Home',
        'body': 'See your live system status, weather, temperature, and AI prediction summaries at a glance.',
      },
      {
        'title': 'Live + Alerts',
        'body': 'Open live CCTV and thermal feeds in Live. Review and manage incident alerts in Alerts.',
      },
      {
        'title': 'Settings + Safety',
        'body': 'Update your account, notification settings, and background monitoring. Use Emergency Alert if needed.',
      },
    ];
    final controller = PageController();
    int currentPage = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text('Welcome to APULA'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 130,
                      width: double.infinity,
                      child: Lottie.asset('assets/fireloading.json', repeat: true),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 190,
                      child: PageView.builder(
                        controller: controller,
                        onPageChanged: (index) {
                          setModalState(() {
                            currentPage = index;
                          });
                        },
                        itemCount: pages.length,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  page['title']!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  page['body']!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 15, height: 1.5),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(pages.length, (index) {
                        final selected = index == currentPage;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: selected ? 18 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: selected ? primary : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Swipe to continue',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: currentPage > 0
                      ? () {
                          controller.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  child: const Text('Back'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (currentPage < pages.length - 1) {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    } else {
                      Navigator.pop(dialogContext);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: primary),
                  child: Text(
                    currentPage < pages.length - 1 ? 'Next' : 'Start',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
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
            if (_availableDevices.isNotEmpty) {
              if (_selectedSimulationCameraId == null ||
                  !_availableDevices.contains(_selectedSimulationCameraId)) {
                _selectedSimulationCameraId = _availableDevices.first;
              }
            } else {
              _selectedSimulationCameraId = null;
            }

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

          _startCnnListener();
        }
      }
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }
  }

  Future<void> _restoreMainStatusCameraSelection() async {
    if (_availableDevices.isEmpty) {
      if (mounted) {
        setState(() {
          _mainStatusCameraId = null;
        });
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _mainStatusCameraId = _availableDevices.first;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'home_main_camera_${user.uid}';
    final saved = prefs.getString(key);

    final selected = (saved != null && _availableDevices.contains(saved))
        ? saved
        : _availableDevices.first;

    if (!mounted) return;
    setState(() {
      _mainStatusCameraId = selected;
    });
  }

  Future<void> _saveMainStatusCameraSelection(String cameraId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('home_main_camera_${user.uid}', cameraId);
  }

  Future<void> _loadSensorStatus(String cameraId) async {
    final status = await SensorPairingHelper.getSensorStatus(cameraId);
    if (!mounted) return;

    setState(() {
      sensorStatusPerCamera[cameraId] = status;
    });
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

  String _now() => DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  String _formatActivityTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _resolveSimulationCameraId([String? preferredCameraId]) {
    final preferred = preferredCameraId?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }

    if (_selectedSimulationCameraId != null &&
        _selectedSimulationCameraId!.isNotEmpty) {
      return _selectedSimulationCameraId!;
    }

    if (_availableDevices.isNotEmpty) {
      return _availableDevices[
          _currentChartPage.clamp(0, _availableDevices.length - 1)];
    }

    return 'cam_01';
  }

  Future<void> _simulateNormal({String? cameraId}) async {
    final targetCameraId = _resolveSimulationCameraId(cameraId);

    final entry = {
      "DHT_Temp": 30,
      "DHT_Humidity": 60,
      "MQ2_Value": 80,
      "Flame_Det": 0,
      "timestamp": _now(),
    };

    try {
      await FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
          .ref("sensor_data/$targetCameraId/latest")
          .set(entry);

      if (!mounted) return;

      setState(() {
        _roomTemp = 30;
        _fireDetected = 0;
        _smokeDetected = 0;
      });

      _addActivity(
        '$targetCameraId: Normal simulation sent',
        _formatActivityTime(DateTime.now()),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Normal data sent to $targetCameraId')),
      );
    } catch (e) {
      debugPrint('Error sending normal simulation: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send normal simulation: $e')),
      );
    }
  }

  Future<void> _simulateIgnition({String? cameraId}) async {
    final targetCameraId = _resolveSimulationCameraId(cameraId);

    final entry = {
      "DHT_Temp": 48,
      "DHT_Humidity": 35,
      "MQ2_Value": 1300,
      "Flame_Det": 1,
      "timestamp": _now(),
    };

    try {
      await FirebaseDatabase.instanceFor(app: yoloFirebaseApp)
          .ref("sensor_data/$targetCameraId/latest")
          .set(entry);

      if (!mounted) return;

      setState(() {
        _roomTemp = 48;
        _fireDetected = 1;
        _smokeDetected = 0;
      });

      _addActivity(
        '$targetCameraId: Ignition simulation sent',
        _formatActivityTime(DateTime.now()),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ignition data sent to $targetCameraId')),
      );
    } catch (e) {
      debugPrint('Error sending ignition simulation: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send ignition simulation: $e')),
      );
    }
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

    CnnListenerService.startListening(_availableDevices, _homeCnnCallback);
  }

  void _handleCnnUpdate(
    String cameraId,
    double alert,
    double severity,
    String snapshotUrl,
    String dominantSource,
  ) {
    if (!mounted) return;

    setState(() {
      // Keep Home callback lightweight to avoid impacting modal responsiveness.
      severityHistoryPerCamera[cameraId] = <double>[severity];
      alertHistoryPerCamera[cameraId] = <double>[alert];
      historyTimestampsPerCamera[cameraId] = <DateTime>[DateTime.now()];

      if (snapshotUrl.isNotEmpty) {
        _lastSnapshotUrl = snapshotUrl;
      }

      if (severity >= THRESH_DEVELOPING && alert >= 0.80) {
        _fireDetected = 1;
        _smokeDetected = 0;
      } else if (severity >= THRESH_IGNITION && alert >= 0.75) {
        _fireDetected = 1;
        _smokeDetected = 0;
      } else if (severity >= THRESH_SMOLDERING && alert >= 0.73) {
        _fireDetected = 0;
        _smokeDetected = 1;
      } else {
        _fireDetected = 0;
        _smokeDetected = 0;
      }
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
      if (recentActivities.length > 6) {
        recentActivities.removeLast();
      }
      _persistedActivities = List<Map<String, dynamic>>.from(recentActivities);
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
      height: double.infinity,
      padding: const EdgeInsets.all(18),
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
                    size: 38,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
                Positioned(
                  top: 34,
                  right: 56 + (drift * 0.7),
                  child: Icon(
                    Icons.cloud,
                    size: 28,
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isDay
                        ? (isCloudy
                            ? Icons.wb_cloudy
                            : (isRainy ? Icons.grain : Icons.wb_sunny))
                        : (isRainy ? Icons.grain : Icons.nightlight_round),
                    color: Colors.white,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _time,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _date,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _weatherLabel(condition),
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_availableDevices.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202020),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _availableDevices.contains(_selectedSimulationCameraId)
                          ? _selectedSimulationCameraId
                          : _availableDevices.first,
                      dropdownColor: const Color(0xFF202020),
                      iconEnabledColor: Colors.white,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      isExpanded: true,
                      items: _availableDevices
                          .map(
                            (cameraId) => DropdownMenuItem<String>(
                              value: cameraId,
                              child: Text('Simulate: ${cameraId.toUpperCase()}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedSimulationCameraId = value;
                        });
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: const Text('Simulate Normal'),
                onPressed: () async {
                  await _simulateNormal(
                    cameraId: _selectedSimulationCameraId,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.local_fire_department),
                label: const Text('Simulate Fire Caution'),
                onPressed: () async {
                  await _simulateIgnition(
                    cameraId: _selectedSimulationCameraId,
                  );
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tempActionButton({
    required String title,
    required Color color,
    required Future<void> Function() onPressed,
  }) {
    return Expanded(
      child: SizedBox(
        height: 42,
        child: ElevatedButton(
          onPressed: () async {
            await onPressed();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildTemperatureCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _showCnnTestModal,
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.all(18),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.thermostat,
              color: Colors.white,
              size: 38,
            ),
            const SizedBox(height: 10),
            Text(
              '$_roomTemp°C',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Room Temperature',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTag(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.toStringAsFixed(3),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildMainPredictionPill(String label, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.toStringAsFixed(3),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPredictionSummary() {
    if (_availableDevices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'No camera available for prediction summary.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }

    final selected = (_mainStatusCameraId != null &&
            _availableDevices.contains(_mainStatusCameraId))
        ? _mainStatusCameraId!
        : _availableDevices.first;

    final severity = (severityHistoryPerCamera[selected] ?? const <double>[]).isEmpty
        ? 0.0
        : severityHistoryPerCamera[selected]!.last;

    final alert = (alertHistoryPerCamera[selected] ?? const <double>[]).isEmpty
        ? 0.0
        : alertHistoryPerCamera[selected]!.last;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Main Camera Prediction',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected,
                isExpanded: true,
                dropdownColor: const Color(0xFF2C2C2C),
                iconEnabledColor: Colors.white,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                items: _availableDevices
                    .map(
                      (cameraId) => DropdownMenuItem<String>(
                        value: cameraId,
                        child: Text(cameraId.toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    _mainStatusCameraId = value;
                  });
                  await _saveMainStatusCameraSelection(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMainPredictionPill('Severity', severity),
              const SizedBox(width: 8),
              _buildMainPredictionPill('Alert', alert),
            ],
          ),
        ],
    );
  }

  Widget _buildMiniCnnBox() {
    if (_availableDevices.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No cameras available',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
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
      padding: const EdgeInsets.all(16),
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
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricTag('Severity', latestSeverity),
              Container(
                width: 1,
                height: 42,
                color: Colors.white24,
              ),
              _buildMetricTag('Alert', latestAlert),
            ],
          ),
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
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        subtitle: Text(
          time,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
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
            padding: const EdgeInsets.all(16),
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
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cameraId.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.sensors, color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sensorStatus,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                label: Text(
                  _chartRangeLabel(range),
                  style: const TextStyle(fontSize: 13),
                ),
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
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          buildSeverityChart(cameraId),
          const SizedBox(height: 20),
          const Text(
            'Alert Prediction',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    CnnListenerService.removeCallbacks(_availableDevices, _homeCnnCallback);
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
        automaticallyImplyLeading: false,
        title: const Text('APULA'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'How this page works',
            onPressed: _showAppGuideModal,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                crossAxisAlignment: CrossAxisAlignment.center,
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
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _buildTimeWeatherCard()),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTemperatureCard()),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Column(
                  children: const [
                    Text(
                      'Emergency Alert',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 10),
                    GlobalManualAlertButton(
                      inline: true,
                      compactCircle: true,
                      forceShowOnHome: true,
                      compactSize: 182,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Tap to send an urgent manual panic alert.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: _availableDevices,
      ),
    );
  }
}