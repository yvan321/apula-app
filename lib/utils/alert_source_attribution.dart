import 'dart:math';

class AlertSourceAttribution {
  static double _clamp01(double value) {
    if (value.isNaN) return 0.0;
    if (value < 0.0) return 0.0;
    if (value > 1.0) return 1.0;
    return value;
  }

  static Map<String, dynamic> fromSignals({
    required double yoloConf,
    required double yoloFireConf,
    required double yoloSmokeConf,
    required double yoloNoFireConf,
    required double temperature,
    required double humidity,
    required double mq2,
    required double flame,
    required double thermalMax,
    required double thermalAvg,
  }) {
    final visionScore = _clamp01(
      (0.55 * yoloFireConf) +
          (0.20 * yoloSmokeConf) +
          (0.15 * yoloConf) -
          (0.25 * yoloNoFireConf),
    );

    final tempScore = _clamp01((temperature - 35.0) / 35.0);
    final smokeScore = _clamp01((mq2 - 250.0) / 2200.0);
    final flameScore = _clamp01(flame);
    final thermalScore = _clamp01(((max(thermalMax, thermalAvg)) - 45.0) / 85.0);
    final drynessScore = _clamp01((60.0 - humidity) / 45.0);

    final sensorScore = _clamp01(
      (0.34 * smokeScore) +
          (0.24 * tempScore) +
          (0.22 * thermalScore) +
          (0.16 * flameScore) +
          (0.04 * drynessScore),
    );

    final delta = (visionScore - sensorScore).abs();
    final dominantSource =
        delta <= 0.12 ? 'mixed' : (visionScore > sensorScore ? 'cctv' : 'sensor');

    return {
      'dominantSource': dominantSource,
      'visionScore': visionScore,
      'sensorScore': sensorScore,
      'confidence': _clamp01(delta),
      'inputs': {
        'yoloConf': yoloConf,
        'yoloFireConf': yoloFireConf,
        'yoloSmokeConf': yoloSmokeConf,
        'yoloNoFireConf': yoloNoFireConf,
        'temperature': temperature,
        'humidity': humidity,
        'mq2': mq2,
        'flame': flame,
        'thermalMax': thermalMax,
        'thermalAvg': thermalAvg,
      },
    };
  }
}
