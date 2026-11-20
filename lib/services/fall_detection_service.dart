import 'package:tflite_flutter/tflite_flutter.dart';

class FallDetectionService {
  Interpreter? _interpreter;

  // Values obtained from the StandardScaler
  // used during model training.
  static const List<double> scalerMean = [
    0.30503696,
    1.15093512,
    -0.27422495,
  ];

  static const List<double> scalerScale = [
    5.07343606,
    8.35024299,
    4.58269702,
  ];

  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/best_mobile_fall_model.tflite',
      );

      print('FALL MODEL: Loaded successfully');

      print(
        'FALL MODEL: Input shape = '
        '${_interpreter!.getInputTensor(0).shape}',
      );

      print(
        'FALL MODEL: Output shape = '
        '${_interpreter!.getOutputTensor(0).shape}',
      );
    } catch (e) {
      print('FALL MODEL ERROR: $e');
    }
  }

  double normalizeValue(
    double value,
    int axis,
  ) {
    return (value - scalerMean[axis]) / scalerScale[axis];
  }

  double predict(List<List<double>> sensorWindow) {
    if (_interpreter == null) {
      throw Exception('Fall detection model is not loaded.');
    }

    if (sensorWindow.length != 151) {
      throw Exception(
        'Expected 151 sensor samples, '
        'but received ${sensorWindow.length}.',
      );
    }

    for (final sample in sensorWindow) {
      if (sample.length != 3) {
        throw Exception(
          'Each sensor sample must contain X, Y and Z values.',
        );
      }
    }

    // Create model input:
    // [batch][time][axis]
    //
    // Shape = [1, 151, 3]
    final input = [
      sensorWindow.map((sample) {
        return [
          normalizeValue(sample[0], 0),
          normalizeValue(sample[1], 1),
          normalizeValue(sample[2], 2),
        ];
      }).toList(),
    ];

    // Output shape = [1, 1]
    final output = [
      [0.0]
    ];

    _interpreter!.run(input, output);

    final probability = output[0][0];

    print(
      'FALL MODEL: Probability = $probability',
    );

    return probability;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}