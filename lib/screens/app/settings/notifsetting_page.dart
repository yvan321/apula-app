import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotifSettingsPage extends StatefulWidget {
  const NotifSettingsPage({super.key});

  @override
  State<NotifSettingsPage> createState() => _NotifSettingsPageState();
}

class _NotifSettingsPageState extends State<NotifSettingsPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _notificationEmailController =
      TextEditingController();
  final List<TextEditingController> _additionalEmailControllers = [];
  bool _isLoading = true;
  bool _isSendingTestEmail = false;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  String? _docId;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _notificationEmailController.dispose();
    for (final controller in _additionalEmailControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _collectAdditionalEmails() {
    return _additionalEmailControllers
        .map((c) => c.text.trim().toLowerCase())
        .where((email) => email.isNotEmpty)
        .toList();
  }

  void _addAdditionalEmailField([String initialValue = ""]) {
    final controller = TextEditingController(text: initialValue);
    _additionalEmailControllers.add(controller);
  }

  void _removeAdditionalEmailField(int index) {
    final controller = _additionalEmailControllers.removeAt(index);
    controller.dispose();
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r"^[\w\.-]+@[\w\.-]+\.[a-zA-Z]{2,}$");
    return regex.hasMatch(email.trim());
  }

  String? _normalizePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return null;

    if (RegExp(r'^\+639\d{9}$').hasMatch(cleaned)) {
      return cleaned;
    }

    if (RegExp(r'^639\d{9}$').hasMatch(cleaned)) {
      return '+$cleaned';
    }

    if (RegExp(r'^09\d{9}$').hasMatch(cleaned)) {
      return '+63${cleaned.substring(1)}';
    }

    return null;
  }

  String _phoneFormatHint() {
    return 'Use PH mobile format: +639XXXXXXXXX, 639XXXXXXXXX, or 09XXXXXXXXX';
  }

  Future<void> _loadUserSettings() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final query = await _firestore
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        _docId = doc.id;

        setState(() {
          _phoneController.text =
              (data['phoneNumber'] ?? data['contact'] ?? '').toString();
          _notificationEmailController.text =
              (data['notificationEmail'] ?? user.email ?? '').toString();

          for (final controller in _additionalEmailControllers) {
            controller.dispose();
          }
          _additionalEmailControllers.clear();

          final additionalEmails =
              List<String>.from(data['additionalEmails'] ?? []);
          for (final email in additionalEmails) {
            _addAdditionalEmailField(email);
          }
        });
      }
    } catch (e) {
      _showSnackBar("Failed to load settings: $e", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final phone = _phoneController.text.trim();
    final notificationEmail = _notificationEmailController.text
        .trim()
        .toLowerCase();
    final additionalEmails = _collectAdditionalEmails();

    final normalizedPrimary = phone.isEmpty ? null : _normalizePhone(phone);
    if (phone.isNotEmpty && normalizedPrimary == null) {
      _showSnackBar(
        "Invalid phone number. ${_phoneFormatHint()}",
        Colors.red,
      );
      return;
    }

    if (notificationEmail.isEmpty || !_isValidEmail(notificationEmail)) {
      _showSnackBar("Please enter a valid notification email.", Colors.red);
      return;
    }

    final invalidEmail = additionalEmails.firstWhere(
      (email) => !_isValidEmail(email),
      orElse: () => "",
    );

    if (invalidEmail.isNotEmpty) {
      _showSnackBar("Invalid email: $invalidEmail", Colors.red);
      return;
    }

    final dedupedAdditionalEmails = additionalEmails
        .where((email) => email != notificationEmail)
        .toSet()
        .toList();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _loadingDialog("Saving your changes..."),
    );

    try {
      final user = _auth.currentUser;
      if (user == null || _docId == null) return;

      await _firestore.collection('users').doc(_docId).update({
        'sendViaSms': false,
        'phoneNumber': normalizedPrimary ?? "",
        'notificationEmail': notificationEmail,
        'additionalEmails': dedupedAdditionalEmails,
        'additionalPhoneNumbers': [],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.pop(context);
            Navigator.pop(context);
          });
          return _successDialog("Notification Settings Saved!");
        },
      );
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar("Something went wrong: $e", Colors.red);
    }
  }

  Future<bool> _saveSettingsSilently() async {
    final phone = _phoneController.text.trim();
    final notificationEmail = _notificationEmailController.text
        .trim()
        .toLowerCase();
    final additionalEmails = _collectAdditionalEmails();

    final normalizedPrimary = phone.isEmpty ? null : _normalizePhone(phone);
    if (phone.isNotEmpty && normalizedPrimary == null) {
      _showSnackBar(
        "Invalid phone number. ${_phoneFormatHint()}",
        Colors.red,
      );
      return false;
    }

    if (notificationEmail.isEmpty || !_isValidEmail(notificationEmail)) {
      _showSnackBar("Please enter a valid notification email.", Colors.red);
      return false;
    }

    final invalidEmail = additionalEmails.firstWhere(
      (email) => !_isValidEmail(email),
      orElse: () => "",
    );

    if (invalidEmail.isNotEmpty) {
      _showSnackBar("Invalid email: $invalidEmail", Colors.red);
      return false;
    }

    final dedupedAdditionalEmails = additionalEmails
        .where((email) => email != notificationEmail)
        .toSet()
        .toList();

    final user = _auth.currentUser;
    if (user == null || _docId == null) {
      _showSnackBar("User settings not loaded. Please try again.", Colors.red);
      return false;
    }

    await _firestore.collection('users').doc(_docId).update({
      'sendViaSms': false,
      'phoneNumber': normalizedPrimary ?? "",
      'notificationEmail': notificationEmail,
      'additionalEmails': dedupedAdditionalEmails,
      'additionalPhoneNumbers': [],
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return true;
  }

  Future<void> _sendTestEmail() async {
    if (_isSendingTestEmail) return;

    setState(() => _isSendingTestEmail = true);

    try {
      final saved = await _saveSettingsSilently();
      if (!saved) return;

      final requestRef = await _firestore.collection('email_test_requests').add({
        'email': _auth.currentUser?.email,
        'uid': _auth.currentUser?.uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      final resultSnap = await requestRef
          .snapshots()
          .firstWhere((snap) {
            final data = snap.data();
            final status = (data?['status'] ?? '').toString().toLowerCase();
            return status == 'sent' || status == 'failed';
          })
          .timeout(const Duration(seconds: 25));

      final result = resultSnap.data() ?? {};
      final status = (result['status'] ?? '').toString().toLowerCase();

      if (status == 'sent') {
        final recipientCount = result['recipientCount'] ?? 0;
        _showSnackBar(
          "Test email sent ($recipientCount recipient${recipientCount == 1 ? '' : 's'}).",
          Colors.green,
        );
      } else {
        final error = (result['error'] ?? 'Failed to send test email.').toString();
        _showSnackBar(error, Colors.red);
      }
    } catch (e) {
      _showSnackBar('Failed to send test email: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSendingTestEmail = false);
      }
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _loadingDialog(String message) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              height: 150,
              width: 150,
              child: Lottie.asset('assets/fireloading.json', repeat: true)),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA30000),
            ),
          ),
        ],
      ),
    );
  }

  Widget _successDialog(String message) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
              height: 150,
              width: 150,
              child: Lottie.asset('assets/check orange.json', repeat: false)),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA30000),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFA30000)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔙 Back Button (above)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: Icon(
                          Icons.chevron_left,
                          size: 30,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),

                  // 🏷️ Title (below)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                    child: Text(
                      "Notification Settings",
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // ⚙️ Settings Body
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: colorScheme.primary.withOpacity(0.5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Emergency Contact Number",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText: "Primary Contact Number",
                                      hintText: "+639123456789",
                                      prefixIcon: const Icon(Icons.phone),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Primary Notification Email",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _notificationEmailController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      labelText: "Notification Email",
                                      hintText: "name@example.com",
                                      prefixIcon: const Icon(Icons.email_outlined),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Additional Email Recipients",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_additionalEmailControllers.isEmpty)
                                    Text(
                                      "No additional emails added.",
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ...List.generate(
                                    _additionalEmailControllers.length,
                                    (index) => Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller:
                                                  _additionalEmailControllers[index],
                                              keyboardType: TextInputType.emailAddress,
                                              decoration: InputDecoration(
                                                labelText: "Email ${index + 1}",
                                                hintText: "name@example.com",
                                                prefixIcon: const Icon(Icons.alternate_email),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _removeAdditionalEmailField(index);
                                              });
                                            },
                                            icon: const Icon(Icons.remove_circle_outline),
                                            color: Colors.red,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _addAdditionalEmailField();
                                        });
                                      },
                                      icon: const Icon(Icons.add),
                                      label: const Text("Add Email"),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _saveSettings,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  "Save Settings",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: OutlinedButton.icon(
                                onPressed: _isSendingTestEmail ? null : _sendTestEmail,
                                icon: _isSendingTestEmail
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.mark_email_read_outlined),
                                label: Text(
                                  _isSendingTestEmail
                                      ? "Sending Test Email..."
                                      : "Send Test Email",
                                  style: TextStyle(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: colorScheme.primary),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
