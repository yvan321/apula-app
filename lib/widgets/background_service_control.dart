import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/background_ai_manager.dart';

class BackgroundServiceControl extends StatefulWidget {
  const BackgroundServiceControl({super.key});

  @override
  State<BackgroundServiceControl> createState() => _BackgroundServiceControlState();
}

class _BackgroundServiceControlState extends State<BackgroundServiceControl> {
  bool _foregroundServiceRunning = false;
  bool _periodicTaskEnabled = false;
  bool _notificationPermissionGranted = false;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _checkServiceStatus();
  }

  Future<void> _initNotifications() async {
    // Request notification permission (Android 13+)
    final status = await Permission.notification.request();
    setState(() {
      _notificationPermissionGranted = status.isGranted;
    });
    if (status.isDenied) {
      print('⚠️ Notification permission denied');
    }
    
    const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifications.initialize(InitializationSettings(android: androidInit));
  }

  Future<void> _sendTestNotification() async {
    // Check permission first
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notification permission not granted. Please enable in settings.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }
    
    const androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Notifications',
      channelDescription: 'Testing notification functionality',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    try {
      await _notifications.show(
        999,
        '🔔 Test Notification',
        'If you see this, notifications are working!',
        NotificationDetails(android: androidDetails),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent!')),
        );
      }
    } catch (e) {
      print('❌ Notification error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _checkServiceStatus() async {
    final isRunning = await BackgroundAIManager.isForegroundServiceRunning();
    final hasCameras = await BackgroundAIManager.hasLinkedCameras();
    setState(() {
      _foregroundServiceRunning = isRunning;
      if (!hasCameras) {
        _periodicTaskEnabled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background AI Services'),
        backgroundColor: const Color(0xFFA30000),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Notification Permission Warning
            if (!_notificationPermissionGranted)
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Notification Permission Required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Background services need notification permission to work. Please grant permission in settings.',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                      SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await openAppSettings();
                          // Recheck after settings
                          Future.delayed(Duration(seconds: 1), () async {
                            final status = await Permission.notification.status;
                            setState(() {
                              _notificationPermissionGranted = status.isGranted;
                            });
                          });
                        },
                        icon: Icon(Icons.settings),
                        label: Text('Open Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!_notificationPermissionGranted) SizedBox(height: 16),
            
            // Foreground Service Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: _foregroundServiceRunning ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Continuous Monitoring',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Runs AI every 5 seconds with persistent notification. Works when app is closed.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_foregroundServiceRunning) {
                          await BackgroundAIManager.stopForegroundService();
                        } else {
                          final started = await BackgroundAIManager.startForegroundService();
                          if (!started && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Connect at least one camera first before enabling monitoring.'),
                              ),
                            );
                          }
                        }
                        await _checkServiceStatus();
                      },
                      icon: Icon(_foregroundServiceRunning ? Icons.stop : Icons.play_arrow),
                      label: Text(_foregroundServiceRunning ? 'Stop Service' : 'Start Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _foregroundServiceRunning
                            ? Colors.red
                            : const Color(0xFFA30000),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Periodic Task Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          color: _periodicTaskEnabled ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Periodic Check (Every 15 min)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Battery efficient. Runs in background every 15 minutes even when app is killed.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (_periodicTaskEnabled) {
                          await BackgroundAIManager.stopPeriodicTask();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Periodic task stopped')),
                          );
                          setState(() {
                            _periodicTaskEnabled = false;
                          });
                        } else {
                          final started = await BackgroundAIManager.startPeriodicTask();
                          if (started) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Periodic task started')),
                            );
                            setState(() {
                              _periodicTaskEnabled = true;
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Connect at least one camera first before enabling monitoring.')),
                            );
                            setState(() {
                              _periodicTaskEnabled = false;
                            });
                          }
                        }
                      },
                      icon: Icon(_periodicTaskEnabled ? Icons.stop : Icons.play_arrow),
                      label: Text(_periodicTaskEnabled ? 'Disable' : 'Enable'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _periodicTaskEnabled
                            ? Colors.red
                            : const Color(0xFFA30000),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Test Notification Button
            ElevatedButton.icon(
              onPressed: _sendTestNotification,
              icon: const Icon(Icons.notifications_active),
              label: const Text('Send Test Notification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 16),

            // Status Display
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📊 Service Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: _foregroundServiceRunning ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text('Continuous: ${_foregroundServiceRunning ? "Running" : "Stopped"}'),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: _periodicTaskEnabled ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text('Periodic: ${_periodicTaskEnabled ? "Enabled" : "Disabled"}'),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: _notificationPermissionGranted ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text('Notifications: ${_notificationPermissionGranted ? "Allowed" : "DENIED"}'),
                      ],
                    ),
                    if (!_notificationPermissionGranted) ...[
                      SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => openAppSettings(),
                        icon: Icon(Icons.settings, size: 16),
                        label: Text('Grant Permission'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                        ),
                      ),
                    ],
                    SizedBox(height: 12),
                    Text(
                      'Tip: Close the app completely and wait for notifications to verify background execution.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Info Card
            const Card(
              color: Color(0xFFFFF3CD),
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFF856404)),
                        SizedBox(width: 8),
                        Text(
                          'Important',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF856404),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Continuous monitoring uses more battery\n'
                      '• Periodic check is more battery efficient\n'
                      '• Both work when app is closed\n'
                      '• Requires stable internet connection',
                      style: TextStyle(color: Color(0xFF856404)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
