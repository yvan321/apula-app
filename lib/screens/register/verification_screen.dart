import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../register/setpassword_screen.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum SnackBarType { success, error, info }

class VerificationScreen extends StatefulWidget {
  final String email;
  const VerificationScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _timer;
  int _secondsRemaining = 120;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  // 🔔 Custom Snackbar
  void _showSnackBar(String message, SnackBarType type) {
    Color bgColor;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        bgColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case SnackBarType.error:
        bgColor = Colors.red;
        icon = Icons.error;
        break;
      case SnackBarType.info:
      default:
        bgColor = Colors.blue;
        icon = Icons.info;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining = 120;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  Future<void> _resendCode() async {
    final newCode = (100000 + Random().nextInt(900000)).toString();

    // 🔍 Find user by email
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: widget.email)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      _showSnackBar("User not found.", SnackBarType.error);
      return;
    }

    final userDoc = query.docs.first;

    // Update code in Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userDoc.id)
        .update({'verificationCode': newCode});

    // Send the new code via backend API
    final url = Uri.parse("http://10.0.2.2:5000/send-verification");
    await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": widget.email, "code": newCode}),
    );

    _startTimer();
    _showSnackBar("A new verification code was sent.", SnackBarType.info);
  }

  Future<void> _confirmCode() async {
    final code = _codeControllers.map((c) => c.text).join();

    if (code.length < 6) {
      _showSnackBar("Please enter the 6-digit code.", SnackBarType.error);
      return;
    }

    try {
      // 🔍 Fetch user by email (not doc ID)
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showSnackBar("User not found.", SnackBarType.error);
        return;
      }

      final userDoc = query.docs.first;
      final storedCode = userDoc.data()['verificationCode'];

      if (storedCode == code) {
        final email = widget.email.toLowerCase();

        // 🚫 Prevent admins from using Flutter app
        if (email.contains("admin")) {
          _showSnackBar(
              "Admins must register and log in via the web.", SnackBarType.error);
          return;
        }

        // ✅ Mark as verified
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDoc.id)
            .update({'verified': true});

        // ✅ Success popup then go to Set Password screen
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            Future.delayed(const Duration(seconds: 2), () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      SetPasswordScreen(email: widget.email),
                ),
              );
            });
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset('assets/check orange.json',
                      repeat: false, height: 200),
                  const SizedBox(height: 20),
                  const Text(
                    "Verification successful!",
                    style: TextStyle(
                      color: Color(0xFFA30000),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      } else {
        _showSnackBar("Invalid code. Please try again.", SnackBarType.error);
      }
    } catch (e) {
      _showSnackBar("Error verifying code: $e", SnackBarType.error);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _codeControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Widget _buildCodeField(int index) {
    return SizedBox(
      width: 50,
      child: TextField(
        controller: _codeControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: "",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFFA30000), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFFA30000), width: 2),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
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
            IconButton(
              icon: Icon(
                Icons.chevron_left,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Text(
                        "Enter Verification Code",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey[600]),
                        children: [
                          const TextSpan(text: "We’ve sent a 6-digit code to "),
                          TextSpan(
                            text: widget.email,
                            style: const TextStyle(
                              color: Color(0xFFA30000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: "."),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // OTP FIELDS 🔢
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children:
                          List.generate(6, (index) => _buildCodeField(index)),
                    ),

                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _confirmCode,
                        child: const Text(
                          "Verify",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: _secondsRemaining > 0
                          ? Text(
                              "Resend available in $_secondsRemaining s",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            )
                          : TextButton(
                              onPressed: _resendCode,
                              child: const Text(
                                "Resend Code",
                                style: TextStyle(
                                  color: Color(0xFFA30000),
                                  fontWeight: FontWeight.bold,
                                ),
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
}
