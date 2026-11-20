import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

class AccelerometerService {
  StreamSubscription<AccelerometerEvent>? _subscription;

  final List<List<double>> _sensorWindow = [];

  // Number of new samples before running the next inference.
  static const int windowSize = 151;
  static const int windowStride = 50;

  int _samplesSinceLastInference = 0;

  void startListening({
    required void Function(List<List<double>> window) onWindowReady,
  }) {
    print('ACCELEROMETER: Starting sensor monitoring...');

    _subscription = accelerometerEventStream().listen(
      (event) {
        _sensorWindow.add([
          event.x,
          event.y,
          event.z,
        ]);

        // Keep only the latest 151 samples.
        if (_sensorWindow.length > windowSize) {
          _sensorWindow.removeAt(0);
        }

        _samplesSinceLastInference++;

        // First inference:
        // wait until we have 151 samples.
        if (_sensorWindow.length < windowSize) {
          return;
        }

        // After the first inference, wait for 50 new samples
        // before sending another window to the model.
        if (_samplesSinceLastInference < windowStride) {
          return;
        }

        _samplesSinceLastInference = 0;

        final window = List<List<double>>.from(
          _sensorWindow.map(
            (sample) => List<double>.from(sample),
          ),
        );

        print(
          'ACCELEROMETER: 151-sample window ready',
        );

        onWindowReady(window);
      },
      onError: (error) {
        print(
          'ACCELEROMETER ERROR: $error',
        );
      },
    );
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;

    _sensorWindow.clear();
    _samplesSinceLastInference = 0;

    print(
      'ACCELEROMETER: Monitoring stopped.',
    );
  }

  void dispose() {
    stopListening();
  }
}