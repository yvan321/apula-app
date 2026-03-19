import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ Import your main and home screens
import '../app/home/home_page.dart';
import '../../services/auth_service.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _sendPasswordReset(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      _showSnackBar("Enter your email first.", Colors.red);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: normalizedEmail);
      if (!mounted) return;
      _showSnackBar("Password reset email sent. Check inbox/spam.", Colors.green);
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? "Failed to send reset email.";
      if (e.code == 'user-not-found') {
        message = "No account found with that email.";
      } else if (e.code == 'invalid-email') {
        message = "Please enter a valid email address.";
      }
      if (!mounted) return;
      _showSnackBar(message, Colors.red);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Failed to send reset email: $e", Colors.red);
    }
  }

  void _openForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: usernameController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Forgot Password"),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: "Enter your account email",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final email = resetEmailController.text;
              Navigator.pop(context);
              await _sendPasswordReset(email);
            },
            child: const Text("Send Reset Link"),
          ),
        ],
      ),
    );
  }

  // ✅ Firebase Login with Firestore role check
 // ✅ Firebase Login with Firestore role check
Future<void> _login() async {
  try {
    final email = usernameController.text.trim().toLowerCase();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Please enter both email and password.", Colors.red);
      return;
    }

    // Firebase authentication
    final userCredential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);

    await userCredential.user?.reload();
    final isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified == true;

    if (!isEmailVerified) {
      await FirebaseAuth.instance.signOut();
      _showSnackBar("Please verify your email first.", Colors.red);
      return;
    }

    // ✅ Fetch user data by email
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      await FirebaseAuth.instance.signOut();
      _showSnackBar("User data not found in database.", Colors.red);
      return;
    }

    final userData = query.docs.first.data();
    final role = (userData['role'] ?? 'User').toString().toLowerCase();

    // 🚫 Block responders and admins
    if (role != 'user') {
      await FirebaseAuth.instance.signOut();
      _showSnackBar(
        "Only regular users can log in here.",
        Colors.red,
      );
      return;
    }

    if (userData['verified'] != true) {
      await query.docs.first.reference.update({'verified': true});
    }

    // ✅ Save login session for persistent login
    await AuthService.saveLoginSession(email);

    // ✅ Successful login
    _showSnackBar("Login successful", Colors.green);
    Navigator.pushReplacementNamed(context, '/home');

  } on FirebaseAuthException catch (e) {
    String errorMessage;
    if (e.code == 'user-not-found') {
      errorMessage = 'No user found for that email.';
    } else if (e.code == 'wrong-password') {
      errorMessage = 'Wrong password provided.';
    } else {
      errorMessage = 'Login failed: ${e.message}';
    }
    _showSnackBar(errorMessage, Colors.red);
  } catch (e) {
    _showSnackBar("Something went wrong: $e", Colors.red);
  }
}

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 100),
                child: Image.asset("assets/logo.png", width: 150),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.55,
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).dialogTheme.backgroundColor ??
                      colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Log In",
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA30000),
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _openForgotPasswordDialog,
                        child: const Text(
                          "Forgot Password?",
                          style: TextStyle(color: Color(0xFFA30000)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA30000),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _login,
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don’t have an account? ",
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/register');
                          },
                          child: const Text(
                            "Sign up",
                            style: TextStyle(
                              color: Color(0xFFA30000),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
