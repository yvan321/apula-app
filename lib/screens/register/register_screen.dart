import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apula/screens/register/map_picker.dart';
import 'package:apula/screens/register/verification_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  double? selectedLat;
  double? selectedLng;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final contact = _contactController.text.trim();
    final address = _addressController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (email.contains("admin")) {
      _showSnackBar("Admin accounts cannot register in the app.", Colors.red);
      return;
    }

    if (name.isEmpty ||
        email.isEmpty ||
        contact.isEmpty ||
        address.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty ||
        selectedLat == null ||
        selectedLng == null) {
      _showSnackBar("All fields must be filled.", Colors.red);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match.", Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar("Password must be at least 6 characters.", Colors.red);
      return;
    }

    if (!email.endsWith("@gmail.com")) {
      _showSnackBar("Email must be @gmail.com", Colors.red);
      return;
    }

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Account creation failed. Please try again.');
      }

      await user.sendEmailVerification();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        "uid": user.uid,
        "name": name,
        "email": email,
        "contact": contact,
        "address": address,
        "latitude": selectedLat,
        "longitude": selectedLng,
        "role": "user",
        "platform": "mobile",
        "verified": false,
        "createdAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Success popup → go to verification
showDialog(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context); // CLOSE POPUP
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationScreen(email: email),
        ),
      );
    });

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 200,
            width: 400,
            child: Lottie.asset("assets/check orange.json", repeat: false),
          ),
          const SizedBox(height: 20),
          const Text(
            "Check your email and verify your account.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA30000),
            ),
          ),
        ],
      ),
    );
  },
);

    } on FirebaseAuthException catch (e) {
      String message = e.message ?? 'Registration failed.';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered.';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak. Use at least 6 characters.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      }
      _showSnackBar(message, Colors.red);
    } catch (e) {
      print('❌ Registration error: $e');
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back Button
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left, size: 30),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Create your account",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA30000),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Name
                    TextField(
                      controller: _nameController,
                      decoration: _input("Full Name"),
                    ),
                    const SizedBox(height: 20),

                    // Email
                    TextField(
                      controller: _emailController,
                      decoration: _input("Email"),
                    ),
                    const SizedBox(height: 20),

                    // Contact
                    TextField(
                      controller: _contactController,
                      decoration: _input("Contact Number"),
                    ),
                    const SizedBox(height: 20),

                    // Address
                    TextField(
                      controller: _addressController,
                      readOnly: true,
                      decoration: _input("Pick Address (Tap to open map)").copyWith(
                        suffixIcon: const Icon(Icons.map),
                      ),
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapPickerScreen(
                              initialAddress: _addressController.text,
                            ),
                          ),
                        );

                        if (result != null && result is Map<String, dynamic>) {
                          _addressController.text = result["address"];
                          selectedLat = result["lat"];
                          selectedLng = result["lng"];
                        }
                      },
                    ),

                    const SizedBox(height: 20),

                    // Password
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: _input("Password"),
                    ),

                    const SizedBox(height: 20),

                    // Confirm Password
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: _input("Confirm Password"),
                    ),

                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFA30000),
                        ),
                        child: const Text(
                          "Register",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
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

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
