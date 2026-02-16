import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    try {
      // Request notification permissions
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permission granted');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('✅ Notification permission provisional');
      } else {
        print('⚠️ Notification permission denied');
        return;
      }

      // Get FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        print('📱 FCM Token: $token');
        await _saveFcmToken(token);
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        print('🔄 FCM Token refreshed: $newToken');
        _saveFcmToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background message (when app is in background/terminated)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      print('✅ FCM initialized successfully');
    } catch (e) {
      print('❌ FCM initialization error: $e');
    }
  }

  /// Save FCM token to Firestore
  static Future<void> _saveFcmToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ No user logged in, skipping FCM token save');
        return;
      }

      final email = user.email;
      if (email == null) return;

      // Update user document with FCM token (in default Firebase)
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        await userQuery.docs.first.reference.update({
          'fcmToken': token,
          'lastFcmUpdate': FieldValue.serverTimestamp(),
        });
        print('✅ FCM token saved for user: $email');
      }
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  /// Handle foreground messages
  static void _handleForegroundMessage(RemoteMessage message) {
    print('📬 Foreground message received:');
    print('  Title: ${message.notification?.title}');
    print('  Body: ${message.notification?.body}');
    print('  Data: ${message.data}');

    // Show local notification
    _showLocalNotification(
      title: message.notification?.title ?? 'APULA Alert',
      body: message.notification?.body ?? '',
      data: message.data,
    );
  }

  /// Handle message when app is opened from notification
  static void _handleMessageOpenedApp(RemoteMessage message) {
    print('🔔 Message opened from terminated state:');
    print('  Title: ${message.notification?.title}');
    print('  Body: ${message.notification?.body}');

    // Navigate to alerts page or relevant screen
    navigatorKey.currentState?.pushNamed('/home');
  }

  /// Show local notification
  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final FlutterLocalNotificationsPlugin notifications =
          FlutterLocalNotificationsPlugin();

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'apula_alerts',
        'APULA Alerts',
        channelDescription: 'Fire detection alerts',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const NotificationDetails notificationDetails =
          NotificationDetails(android: androidDetails);

      await notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        notificationDetails,
      );

      print('✅ Local notification shown');
    } catch (e) {
      print('❌ Error showing notification: $e');
    }
  }
}
