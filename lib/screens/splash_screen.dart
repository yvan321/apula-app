import 'package:flutter/material.dart';
import 'get_started_screen.dart';
import 'app/home/home_page.dart';
import '../services/auth_service.dart';
import '../services/location_restriction_service.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Wait for splash animation
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    // Check if user has valid session and auto-login
    final isLoggedIn = await AuthService.autoLogin();

    if (!mounted) return;

    if (isLoggedIn) {
      // Check if user is within Bacoor, Cavite city
      final locationCheck = await LocationRestrictionService.checkIfInBacoor();
      
      if (!mounted) return;

      if (!locationCheck['hasLocation']) {
        // No location available, show warning but allow entry
        _showLocationWarningDialog(
          title: 'Location Services Required',
          message: locationCheck['message'],
          allowEntry: true,
          onContinue: () => _navigateToHome(),
        );
      } else if (!locationCheck['isInBacoor']) {
        // User is outside Bacoor, Cavite
        _showLocationWarningDialog(
          title: 'Location Warning',
          message: 'You are outside Bacoor, Cavite.\n\nCurrent location: ${locationCheck['city'] ?? 'Unknown'}\n\nAPULA is currently focused on Bacoor operations.\n\nContinue at your own risk.',
          allowEntry: true,
          onContinue: () => _navigateToHome(),
        );
      } else {
        // User is in Bacoor, proceed normally
        _navigateToHome();
      }
    } else {
      // No valid session, go to get started screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const GetStartedScreen(),
        ),
      );
    }
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const HomePage(),
      ),
    );
  }

  void _showLocationWarningDialog({
    required String title,
    required String message,
    required bool allowEntry,
    required VoidCallback onContinue,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (allowEntry)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onContinue();
              },
              child: const Text('Continue'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Sign out and return to get started
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const GetStartedScreen(),
                ),
              );
            },
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFFA30000)],
          ),
        ),
        child: Center(
          child: Image.asset(
            "assets/logo.png",
            width: 150,
          ),
        ),
      ),
    );
  }
}
