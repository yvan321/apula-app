import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
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

  double? selectedLat;
  double? selectedLng;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
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

    if (email.contains("admin")) {
      _showSnackBar("Admin accounts cannot register in the app.", Colors.red);
      return;
    }

    if (name.isEmpty ||
        email.isEmpty ||
        contact.isEmpty ||
        address.isEmpty ||
        selectedLat == null ||
        selectedLng == null) {
      _showSnackBar("All fields must be filled.", Colors.red);
      return;
    }

    if (!email.endsWith("@gmail.com")) {
      _showSnackBar("Email must be @gmail.com", Colors.red);
      return;
    }

    try {
      // Create verification code
      final code = (100000 + Random().nextInt(900000)).toString();

      // Save temporary user to Firestore (Auto ID)
      final newUser = await FirebaseFirestore.instance.collection('users').add({
        "name": name,
        "email": email,
        "contact": contact,
        "address": address,
        "latitude": selectedLat,
        "longitude": selectedLng,
        "role": "user",
        "platform": "mobile",
        "verificationCode": code,
        "verified": false,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Send email to backend
      final url = Uri.parse("http://localhost:3007/send-verification");
      await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "code": code}),
      );

      // Success popup → go to verification
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
            "Check your email for the verification code!",
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

    } catch (e) {
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
