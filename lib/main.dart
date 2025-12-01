import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

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

import 'services/cnn_listener_service.dart';
import 'services/background_cnn_service.dart';
import 'services/global_alert_handler.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late FirebaseApp yoloFirebaseApp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  yoloFirebaseApp = await Firebase.initializeApp(
    name: "yoloApp",
    options: FirebaseYoloOptions.options,
  );

  CnnListenerService.simulationOnly = false;
  await BackgroundCnnService.initialize(yoloFirebaseApp);

  // 👉 NOW listener expects 3 params: (alert, severity, snapshotUrl)
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
      ),
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
        '/live_footage': (_) =>
            const LiveFootagePage(devices: ["CCTV1", "CCTV2"]),
        '/live_camera_view': (context) {
          final deviceName =
              ModalRoute.of(context)!.settings.arguments as String;
          return LiveCameraViewPage(deviceName: deviceName);
        },
        '/account_settings': (_) => const AccountSettingsPage(),
        '/about': (_) => const AboutPage(),
        '/notifsettings_page': (_) => const NotifSettingsPage(),
        '/pickLocation': (_) => const MapPickerScreen(),
      },
    );
  }
}
