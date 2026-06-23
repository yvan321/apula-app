import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:apula/main.dart';
import 'package:apula/services/cnn_listener_service.dart';
import 'package:apula/utils/app_palette.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';

class PredictionPage extends StatefulWidget {
  final List<String> availableDevices;

  const PredictionPage({super.key, required this.availableDevices});

  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  int _selectedIndex = 2;
  String? _selectedCameraId;
  late final CnnCallback _predictionCallback;
  Set<String> _listeningDevices = <String>{};

  final Map<String, List<double>> _severityByCamera = {};
  final Map<String, List<double>> _alertByCamera = {};

  static const int _maxPoints = 120;

  @override
  void initState() {
    super.initState();
    _predictionCallback = _onCnnUpdate;
    _syncDeviceListeners(widget.availableDevices);
  }

  @override
  void didUpdateWidget(covariant PredictionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDeviceListeners(widget.availableDevices);
  }

  @override
  void dispose() {
    if (_listeningDevices.isNotEmpty) {
      CnnListenerService.removeCallbacks(_listeningDevices.toList(), _predictionCallback);
    }
    super.dispose();
  }

  void _syncDeviceListeners(List<String> devices) {
    final next = devices.toSet();

    final toAdd = next.difference(_listeningDevices).toList();
    final toRemove = _listeningDevices.difference(next).toList();

    if (toAdd.isNotEmpty) {
      _loadHistoricalPoints(toAdd);
      CnnListenerService.startListening(toAdd, _predictionCallback);
      _primeLatestPoints(toAdd);
    }
    if (toRemove.isNotEmpty) {
      CnnListenerService.removeCallbacks(toRemove, _predictionCallback);
    }

    _listeningDevices = next;

    if (_selectedCameraId == null || !next.contains(_selectedCameraId)) {
      _selectedCameraId = devices.isNotEmpty ? devices.first : null;
    }
  }

  Future<void> _primeLatestPoints(List<String> cameraIds) async {
    if (cameraIds.isEmpty) return;

    final rtdb = FirebaseDatabase.instanceFor(app: yoloFirebaseApp);

    for (final cameraId in cameraIds) {
      try {
        if ((_severityByCamera[cameraId] ?? const <double>[]).isNotEmpty &&
            (_alertByCamera[cameraId] ?? const <double>[]).isNotEmpty) {
          continue;
        }

        final snap = await rtdb.ref('cnn_results/$cameraId').get();
        if (!mounted || !snap.exists || snap.value is! Map) continue;

        final data = Map<String, dynamic>.from(snap.value as Map);
        final severity = _toDouble(data['severity']);
        final alert = _toDouble(data['alert']);

        setState(() {
          _severityByCamera.putIfAbsent(cameraId, () => []);
          _alertByCamera.putIfAbsent(cameraId, () => []);

          _severityByCamera[cameraId]!.add(severity);
          _alertByCamera[cameraId]!.add(alert);

          if (_severityByCamera[cameraId]!.length > _maxPoints) {
            _severityByCamera[cameraId]!.removeAt(0);
          }
          if (_alertByCamera[cameraId]!.length > _maxPoints) {
            _alertByCamera[cameraId]!.removeAt(0);
          }
        });
      } catch (_) {
        // Keep page responsive even if one camera read fails.
      }
    }
  }

  Future<void> _loadHistoricalPoints(List<String> cameraIds) async {
    if (cameraIds.isEmpty) return;

    for (final cameraId in cameraIds) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('cnn_history')
            .doc(cameraId)
            .collection('points')
            .orderBy('ts', descending: true)
            .limit(_maxPoints)
            .get();

        if (!mounted || snap.docs.isEmpty) continue;

        final docs = snap.docs.reversed;
        final severity = <double>[];
        final alert = <double>[];

        for (final doc in docs) {
          final data = doc.data();
          severity.add(_toDouble(data['severity']));
          alert.add(_toDouble(data['alert']));
        }

        setState(() {
          _severityByCamera[cameraId] = severity;
          _alertByCamera[cameraId] = alert;
        });
      } catch (_) {
        // Ignore one camera failure and continue loading the rest.
      }
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  void _onCnnUpdate(
    String cameraId,
    double alert,
    double severity,
    String snapshotUrl,
    String dominantSource,
  ) {
    if (!mounted) return;

    setState(() {
      _severityByCamera.putIfAbsent(cameraId, () => []);
      _alertByCamera.putIfAbsent(cameraId, () => []);

      _severityByCamera[cameraId]!.add(severity);
      _alertByCamera[cameraId]!.add(alert);

      if (_severityByCamera[cameraId]!.length > _maxPoints) {
        _severityByCamera[cameraId]!.removeAt(0);
      }
      if (_alertByCamera[cameraId]!.length > _maxPoints) {
        _alertByCamera[cameraId]!.removeAt(0);
      }

      _selectedCameraId ??= cameraId;
    });
  }

  void _showGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Predictions Guide'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Select a camera from the dropdown.'),
            SizedBox(height: 8),
            Text('2. Check the latest Severity and Alert values.'),
            SizedBox(height: 8),
            Text('3. Read the line graphs to see trend over time.'),
            SizedBox(height: 8),
            Text('Severity: closer to 1 means stronger fire probability.'),
            SizedBox(height: 8),
            Text('Alert: closer to 1 means stronger alert confidence.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required List<double> values,
    required Color lineColor,
    required String description,
  }) {
    final spots = <FlSpot>[];
    for (int i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i].clamp(0.0, 1.0)));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.black87 : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final mutedText = isDark ? Colors.white70 : Colors.black54;
    final gridColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 1,
                minX: 0,
                maxX: spots.length <= 1 ? 5 : (spots.length - 1).toDouble(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  getDrawingHorizontalLine: (value) =>
                    FlLine(color: gridColor, strokeWidth: 1),
                  getDrawingVerticalLine: (value) =>
                    FlLine(color: gridColor, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 0.2,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(1),
                        style: TextStyle(color: mutedText, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 3,
                    color: lineColor,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColor.withOpacity(0.25),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(color: mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.availableDevices;
    final selected = _selectedCameraId;
    final severity = selected == null ? <double>[] : (_severityByCamera[selected] ?? <double>[]);
    final alert = selected == null ? <double>[] : (_alertByCamera[selected] ?? <double>[]);

    final latestSeverity = severity.isEmpty ? 0.0 : severity.last;
    final latestAlert = alert.isEmpty ? 0.0 : alert.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Predictions'),
        actions: [
          IconButton(
            tooltip: 'How this page works',
            onPressed: _showGuideDialog,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: devices.isEmpty
            ? const Center(
                child: Text('No cameras available yet.'),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: devices.contains(selected) ? selected : devices.first,
                          isExpanded: true,
                          items: devices
                              .map(
                                (cameraId) => DropdownMenuItem<String>(
                                  value: cameraId,
                                  child: Text(cameraId.toUpperCase()),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedCameraId = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppPalette.secondaryWarm, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Latest Prediction - ${(selected ?? devices.first).toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Text('Severity'),
                                  Text(latestSeverity.toStringAsFixed(3)),
                                ],
                              ),
                              Column(
                                children: [
                                  const Text('Alert'),
                                  Text(latestAlert.toStringAsFixed(3)),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _chartCard(
                      title: 'Severity Trend',
                      values: severity,
                      lineColor: Colors.orange,
                      description:
                          'Severity estimates fire intensity/risk. Low means safer conditions; high means stronger fire likelihood.',
                    ),
                    _chartCard(
                      title: 'Alert Trend',
                      values: alert,
                      lineColor: Colors.blue,
                      description:
                          'Alert reflects confidence for raising warning/incident actions. Higher values indicate stronger alert confidence.',
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (_) {},
        availableDevices: devices,
      ),
    );
  }
}
