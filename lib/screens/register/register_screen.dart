import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/gestures.dart';
import 'package:apula/screens/register/map_picker.dart';
import 'package:apula/screens/register/verification_screen.dart';
import 'package:apula/screens/legal/terms_screen.dart';
import 'package:apula/screens/legal/privacy_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _registerTutorialShownKey =
      'register_tutorial_shown_v1';
  static const String _tosVersion = '2026-06-10';
  static const String _privacyVersion = '2026-06-10';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  bool _acceptedTerms = false;

  double? selectedLat;
  double? selectedLng;
  bool _isResolvingCurrentLocation = false;

  final RegExp _fullNameRegex = RegExp(r'^[A-Za-z]+(?:\s+[A-Za-z]+)*$');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTutorial();
    });
  }

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

    if (!_fullNameRegex.hasMatch(name)) {
      _showSnackBar(
        "Full name must contain letters and spaces only.",
        Colors.red,
      );
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
      if (!_acceptedTerms) {
        _showSnackBar("You must accept Terms and Privacy Policy.", Colors.red);
        return;
      }
      final tempPassword = _generateTemporaryPassword();
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: tempPassword);

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
        // Proof of acceptance
        "accepted_tos": true,
        "accepted_tos_version": _tosVersion,
        "accepted_tos_at": FieldValue.serverTimestamp(),
        "accepted_privacy_version": _privacyVersion,
        "accepted_privacy_at": FieldValue.serverTimestamp(),
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

  Future<void> _openMapPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialAddress: _addressController.text,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      _addressController.text = (result["address"] ?? '').toString();
      selectedLat = (result["lat"] as num?)?.toDouble();
      selectedLng = (result["lng"] as num?)?.toDouble();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _useCurrentLocationForAddress() async {
    if (_isResolvingCurrentLocation) return;

    if (mounted) {
      setState(() {
        _isResolvingCurrentLocation = true;
      });
    }

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showSnackBar("Location services are disabled.", Colors.red);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnackBar("Location permission is required.", Colors.red);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String resolvedAddress =
          'Lat ${position.latitude.toStringAsFixed(6)}, Lng ${position.longitude.toStringAsFixed(6)}';

      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.name,
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
            p.postalCode,
          ]
              .where((part) => part != null && part!.trim().isNotEmpty)
              .cast<String>()
              .toList();
          if (parts.isNotEmpty) {
            resolvedAddress = parts.join(', ');
          }
        }
      } catch (_) {
        // Keep coordinates fallback if reverse geocoding fails.
      }

      _addressController.text = resolvedAddress;
      selectedLat = position.latitude;
      selectedLng = position.longitude;
      _showSnackBar("Current location applied to address.", Colors.green);
    } catch (e) {
      _showSnackBar("Unable to use current location: $e", Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingCurrentLocation = false;
        });
      }
    }
  }

  Future<void> _maybeShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool(_registerTutorialShownKey) ?? false;
    if (shown || !mounted) return;

    await _showTutorialModal();
    await prefs.setBool(_registerTutorialShownKey, true);
  }

  Future<void> _showTutorialModal() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Quick Registration Guide'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Enter your full name (letters and spaces only).'),
            SizedBox(height: 8),
            Text('2. Tap the map/search icon to pick an address.'),
            SizedBox(height: 8),
            Text('3. Use the location icon to auto-fill your current address.'),
            SizedBox(height: 8),
            Text('4. Verify email, then set your password on next screen.'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA30000),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
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
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z\s]')),
                      ],
                      textCapitalization: TextCapitalization.words,
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
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.search),
                              tooltip: 'Search address on map',
                              onPressed: _openMapPicker,
                            ),
                            IconButton(
                              icon: _isResolvingCurrentLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location),
                              tooltip: 'Use current location',
                              onPressed: _isResolvingCurrentLocation
                                  ? null
                                  : _useCurrentLocationForAddress,
                            ),
                          ],
                        ),
                      ),
                      onTap: _openMapPicker,
                    ),

                    const SizedBox(height: 20),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _showTutorialModal,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text("View quick guide"),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          onChanged: (v) {
                            setState(() {
                              _acceptedTerms = v ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _acceptedTerms = !_acceptedTerms;
                              });
                            },
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black87),
                                children: [
                                  const TextSpan(text: 'I agree to the '),
                                  TextSpan(
                                    text: 'Terms of Service',
                                    style: const TextStyle(color: Color(0xFFA30000), decoration: TextDecoration.underline),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const TermsScreen()),
                                        );
                                      },
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: const TextStyle(color: Color(0xFFA30000), decoration: TextDecoration.underline),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const PrivacyScreen()),
                                        );
                                      },
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _acceptedTerms ? _register : null,
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

  String _generateTemporaryPassword() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'ApulaTmp!${micros.toRadixString(36)}';
  }
}
