import 'package:flutter/material.dart';
import 'get_started_screen.dart';
import 'app/home/home_page.dart';
import '../services/auth_service.dart'; 

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
      // User is logged in, go directly to home
      Navigator.pushReplacementNamed(context, '/home');
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
