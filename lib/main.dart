import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // your app's generated options
import 'firebase_yolo_options.dart'; // YOLO RTDB FirebaseOptions (you already have this)

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

import 'services/background_cnn_service.dart';
import 'services/global_alert_handler.dart'; // for manual testing if needed

// ⭐ GLOBAL navigatorKey for showing dialogs anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// YOLO RTDB Firebase app handle (initialized in main)
late FirebaseApp yoloFirebaseApp;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Main Firebase (Firestore / primary app)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // YOLO RTDB Firebase (separate project / RTDB)
  yoloFirebaseApp = await Firebase.initializeApp(
    name: "yoloApp",
    options: FirebaseYoloOptions.options,
  );

  // Start background CNN service (pass the YOLO firebase app)
  await BackgroundCnnService.initialize(yoloFirebaseApp);

  // OPTIONAL: quick manual test of modal (uncomment if needed)
  // Future.delayed(Duration(seconds: 1), () {
  //   GlobalAlertHandler.showFireModal(
  //     alert: 0.9,
  //     severity: 0.9,
  //     snapshotUrl: "",
  //     deviceName: "CCTV1",
  //   );
  // });

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
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      title: "Apula",
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
        ).copyWith(primary: primaryRed, secondary: primaryRed),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
          brightness: Brightness.dark,
        ).copyWith(primary: primaryRed, secondary: primaryRed),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/verification': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          String email = "";
          if (args is String) {
            email = args;
          } else if (args is Map) {
            email = args["email"] ?? "";
          }
          return VerificationScreen(email: email);
        },
        '/home': (context) => const HomePage(),
        '/add_device': (context) => const AddDeviceScreen(),
        '/devices_info': (context) => const DevicesInfoScreen(),
        '/live_footage': (context) =>
            const LiveFootagePage(devices: ["CCTV1", "CCTV2"]),
        '/live_camera_view': (context) {
          final deviceName =
              ModalRoute.of(context)!.settings.arguments as String;
          return LiveCameraViewPage(deviceName: deviceName);
        },
        '/account_settings': (context) => const AccountSettingsPage(),
        '/about': (context) => const AboutPage(),
        '/notifsettings_page': (context) => const NotifSettingsPage(),
        '/pickLocation': (context) => const MapPickerScreen(),
      },
    );
  }
}
