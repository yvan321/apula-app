import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({Key? key}) : super(key: key);

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen>
    with SingleTickerProviderStateMixin {
  String? qrResult;

  // 🔴 Animation for scanner line
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0, end: 1).animate(_animationController);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
  final String? code = capture.barcodes.first.rawValue;

  if (code != null && mounted) {
    setState(() {
      qrResult = code;
    });

    // stop camera when navigating
    MobileScannerController().stop();

    Navigator.pushReplacementNamed(
      context,
      '/devices_info',
      arguments: code,
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final double scanBoxSize = 250;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 📷 Camera View
            MobileScanner(
              fit: BoxFit.cover,
              onDetect: _onDetect,
            ),

            // 🔲 Dark overlay with cutout
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.6),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: scanBoxSize,
                      height: scanBoxSize,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 📌 Scanner Box with corners + line
            Center(
              child: SizedBox(
                width: scanBoxSize,
                height: scanBoxSize,
                child: Stack(
                  children: [
                    // 🟦 Corner borders only
                    Positioned.fill(
                      child: CustomPaint(painter: CornerPainter()),
                    ),

                    // 🔴 Moving line
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return Positioned(
                          top: _animation.value * (scanBoxSize - 2),
                          left: 0,
                          right: 0,
                          child: Container(height: 2, color: Colors.red),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // 🔙 Back button
            Positioned(
              top: 20,
              left: 10,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Color(0xFFA30000),
                  size: 28,
                ),
              ),
            ),

            // 📌 Title
            const Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  "Scan Device",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA30000),
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

// 🎨 Custom painter for scanner corners
class CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFA30000)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    const double cornerLength = 30;

    // Top-left
    canvas.drawLine(const Offset(0, 0), const Offset(cornerLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, cornerLength), paint);

    // Top-right
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLength, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
