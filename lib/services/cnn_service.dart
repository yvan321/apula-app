// lib/services/cnn_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class CnnService {
  late Interpreter _interpreter;
  late List<double> _means;
  late List<double> _stds;

  bool initialized = false;

  Future<void> init() async {
    if (initialized) return;

    // Load model
    _interpreter = await Interpreter.fromAsset(
      "assets/models/APULA_FUSION_CNN_v2.tflite",
      options: InterpreterOptions()..threads = 2,
    );

    // Load scaler JSON
    final scalerJson =
        await rootBundle.loadString("assets/models/feature_scaler.json");

    final scaler = jsonDecode(scalerJson);

    _means = List<double>.from(scaler["mean"]);
    _stds = List<double>.from(scaler["std"]);

    initialized = true;
  }

  // Normalize input vector
  List<double> _scale(List<double> x) {
    List<double> out = [];
    for (int i = 0; i < x.length; i++) {
      out.add((x[i] - _means[i]) / _stds[i]);
    }
    return out;
  }

  /// RUN INFERENCE
  Map<String, double> runInference({
    required double yoloConf,
    required double temp,
    required double humidity,
    required double smokePpm,
    required double flame,
    required double thermalMax,
    required double thermalAvg,
    required double yoloFire,
    required double yoloSmoke,
    required double yoloNoFire,
  }) {
    final input = [
      yoloConf,
      temp,
      humidity,
      smokePpm,
      flame,
      thermalMax,
      thermalAvg,
      yoloFire,
      yoloSmoke,
      yoloNoFire,
    ];

    final scaled = _scale(input);

    final inputTensor = [scaled];
    final outputTensor = List.filled(2, 0.0).reshape([1, 2]);

    _interpreter.run(inputTensor, outputTensor);

    return {
      "severity": outputTensor[0][0],
      "alert": outputTensor[0][1],
    };
  }
}
