import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TermsScreen extends StatefulWidget {
  const TermsScreen({Key? key}) : super(key: key);

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  String _text = '';

  @override
  void initState() {
    super.initState();
    _loadText();
  }

  Future<void> _loadText() async {
    try {
      final data = await rootBundle.loadString('assets/legal/terms.md');
      setState(() => _text = data);
    } catch (e) {
      setState(() => _text = 'Unable to load Terms of Service.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(_text, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}
