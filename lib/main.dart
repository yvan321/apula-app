import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

void main() {
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
      title: "Apula",
      themeMode: themeProvider.themeMode, // 👈 Controlled by SettingsPage
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
        ).copyWith(primary: primaryRed, secondary: primaryRed),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: const TextStyle(color: primaryRed),
          hintStyle: const TextStyle(color: Colors.black54),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: primaryRed),
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: primaryRed),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryRed,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: primaryRed),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryRed,
            side: const BorderSide(color: primaryRed),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
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
          final email = ModalRoute.of(context)!.settings.arguments as String;
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
      },
    );
  }
}
