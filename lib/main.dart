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
import 'widgets/global_manual_alert_button.dart';

import 'services/cnn_listener_service.dart';
import 'services/background_cnn_service.dart';
import 'services/global_alert_handler.dart';
import 'services/background_ai_manager.dart';
import 'services/fcm_service.dart';
import 'utils/app_palette.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<String?> currentRouteName = ValueNotifier<String?>(null);
final ValueNotifier<bool> hasPopupRoute = ValueNotifier<bool>(false);
final AppRouteObserver appRouteObserver = AppRouteObserver();
late FirebaseApp yoloFirebaseApp;

class AppRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  void _syncState() {
    Route<dynamic>? topPageRoute;
    for (final route in _routes.reversed) {
      if (route is PageRoute<dynamic>) {
        topPageRoute = route;
        break;
      }
    }

    currentRouteName.value = topPageRoute?.settings.name;
    hasPopupRoute.value = _routes.isNotEmpty && _routes.last is PopupRoute<dynamic>;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _syncState();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _syncState();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _syncState();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _routes.remove(oldRoute);
    }
    if (newRoute != null) {
      _routes.add(newRoute);
    }
    _syncState();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

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

  // Do not auto-start monitoring here. Start/stop is user-controlled
  // from the in-app background service controls after login.

  // Initialize FCM for push notifications
  await FcmService.initialize();

  // Note: Global CNN listener will be initialized per-camera in HomePage
  // after devices are loaded from Firestore

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider()..init(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  TextTheme _buildAccessibleTextTheme(TextTheme base) {
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 34, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w600),
      titleLarge: base.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
      bodySmall: base.bodySmall?.copyWith(fontSize: 14, height: 1.35),
      labelLarge: base.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // Light theme
    final lightScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primaryFire,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppPalette.primaryFire,
      secondary: AppPalette.secondaryWarm,
      tertiary: AppPalette.actionTeal,
      error: AppPalette.emergencyRed,
      surface: AppPalette.lightCard,
    );

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: lightScheme,
      textTheme: _buildAccessibleTextTheme(ThemeData(brightness: Brightness.light).textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.lightCard,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      scaffoldBackgroundColor: AppPalette.lightBackground,
      cardColor: AppPalette.lightCard,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.actionTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.actionTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFFF0F0F0),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    // Dark theme
    final darkScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primaryFire,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppPalette.secondaryWarm,
      secondary: AppPalette.primaryFire,
      tertiary: AppPalette.actionTeal,
      error: AppPalette.emergencyRed,
      surface: AppPalette.darkCard,
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: darkScheme,
      textTheme: _buildAccessibleTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.darkCard,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      scaffoldBackgroundColor: AppPalette.darkBackground,
      cardColor: AppPalette.darkCard,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.actionTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.actionTeal,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: const Color(0xFF2A2A2A),
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [appRouteObserver],
      debugShowCheckedModeBanner: false,
      title: "Apula",
      themeMode: themeProvider.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      builder: (context, child) {
        return ValueListenableBuilder<String?>(
          valueListenable: currentRouteName,
          builder: (context, routeName, _) {
            final isDashboard = routeName == '/home';
            return Stack(
              children: [
                if (child != null) child,
                if (isDashboard) const GlobalManualAlertButton(),
              ],
            );
          },
        );
      },
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
