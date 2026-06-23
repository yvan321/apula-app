import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({Key? key}) : super(key: key);

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  String _text = '';

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  Future<void> _loadText() async {
    try {
      final data = await rootBundle.loadString('assets/legal/privacy.md');
      setState(() => _text = data);
    } catch (e) {
      setState(() => _text = 'Unable to load Privacy Policy.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(_text, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
