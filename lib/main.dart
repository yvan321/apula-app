import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'firebase_options.dart';
import 'firebase_yolo_options.dart';

import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/register/add_device.dart';
import 'screens/register/verification_screen.dart';
import 'screens/device/devices_info.dart';
import 'screens/app/home/home_page.dart';
import 'screens/app/live/livefootage_page.dart';
import 'screens/app/live/live_camera_view_page.dart';
import 'screens/app/settings/account_settings_page.dart';
import 'screens/app/settings/about_page.dart';
import 'screens/app/settings/notifsetting_page.dart';
import 'screens/register/map_picker.dart';

import 'widgets/background_service_control.dart';

import 'services/cnn_listener_service.dart';
import 'services/background_cnn_service.dart';
import 'services/global_alert_handler.dart';
import 'services/background_ai_manager.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late FirebaseApp yoloFirebaseApp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 REQUIRED FOR ANDROID WEBVIEW VIDEO + HLS
  AndroidWebViewController.enableDebugging(true);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  yoloFirebaseApp = await Firebase.initializeApp(
    name: "yoloApp",
    options: FirebaseYoloOptions.options,
  );

  await BackgroundCnnService.initialize(yoloFirebaseApp);

  // Initialize background AI services
  await BackgroundAIManager.initWorkManager();
  BackgroundAIManager.initForegroundTask();

  // REGISTER GLOBAL FIRE MODAL LISTENER
  CnnListenerService.startListening((alert, severity, snapshotUrl) {
    GlobalAlertHandler.showFireModal(
      alert: alert,
      severity: severity,
      snapshotUrl: snapshotUrl,
      deviceName: "CCTV1",
    );
  });

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFA30000);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Apula",
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryRed),
      ),
      darkTheme: ThemeData.dark().copyWith(useMaterial3: true),
      initialRoute: "/",
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/verification': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          String email = "";
          if (args is String) email = args;
          if (args is Map) email = args["email"] ?? "";
          return VerificationScreen(email: email);
        },
        '/home': (_) => const HomePage(),
        '/add_device': (_) => const AddDeviceScreen(),
        '/devices_info': (_) => const DevicesInfoScreen(),
        '/live_footage': (_) => const _LiveFootageLoader(),
        '/live_camera_view': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

          return LiveCameraViewPage(
            deviceName: args["deviceName"],
            cameraId: args["cameraId"],
          );
        },
        '/account_settings': (_) => const AccountSettingsPage(),
        '/about': (_) => const AboutPage(),
        '/notifsettings_page': (_) => const NotifSettingsPage(),
        '/background_services': (_) => const BackgroundServiceControl(),
        '/pickLocation': (_) => const MapPickerScreen(),
      },
    );
  }
}

// Helper widget to load devices from Firestore
class _LiveFootageLoader extends StatelessWidget {
  const _LiveFootageLoader();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return const LiveFootagePage(devices: []);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const LiveFootagePage(devices: []);
        }

        final userData = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final List<dynamic>? cameraIds = userData['cameraIds'];
        final List<String> devices = cameraIds != null 
            ? List<String>.from(cameraIds) 
            : [];

        return LiveFootagePage(devices: devices);
      },
    );
  }
}
