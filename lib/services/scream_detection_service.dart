
import 'dart:async';


import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../utils/scream_audio_preprocessor.dart';

class ScreamDetectionService {
  AudioRecorder? _recorder;
  Interpreter? _interpreter;
  StreamSubscription<Uint8List>? _audioSubscription;

  final List<double> _audioSamples = <double>[];

  final ScreamAudioPreprocessor _preprocessor =
      ScreamAudioPreprocessor();

  static const int windowSamples = 160000;
  static const double detectionThreshold = 0.55;

  bool _isListening = false;
  bool _isProcessing = false;
  bool _isDisposed = false;

  // Epoch timestamp in milliseconds. Null means Smart Mute is off.
  int? _mutedUntilEpochMs;

  // Used to invalidate predictions started before a mute-state change.
  int _muteGeneration = 0;

  bool get isListening => _isListening;

  bool get isSmartMuteActive {
    final until = _mutedUntilEpochMs;

    return until != null &&
        until > DateTime.now().millisecondsSinceEpoch;
  }

  /// Set the Smart Mute expiry timestamp in milliseconds since epoch.
  ///
  /// Pass null or 0 to turn Smart Mute off immediately.
  /// Pass a future timestamp to mute scream detection until that time.
  void setMutedUntilMillis(int? untilMs) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (untilMs == null || untilMs <= now) {
      _mutedUntilEpochMs = null;
      debugPrint('SCREAM: Smart Mute is OFF.');
    } else {
      _mutedUntilEpochMs = untilMs;
      debugPrint(
        'SCREAM: Smart Mute active until '
        '${DateTime.fromMillisecondsSinceEpoch(untilMs)}',
      );
    }

    // Invalidate any inference that started before this change.
    _muteGeneration++;

    // Never process audio captured before or during the mute transition.
    _audioSamples.clear();
  }

  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError(
        'ScreamDetectionService has been disposed.',
      );
    }

    debugPrint('SCREAM: Initializing detector...');

    _recorder ??= AudioRecorder();

    if (!await _recorder!.hasPermission()) {
      throw Exception('Microphone permission was not granted.');
    }

    _interpreter ??= await Interpreter.fromAsset(
      'assets/models/scream_detection_model.tflite',
    );

    debugPrint(
      'SCREAM: Input shape: '
      '${_interpreter!.getInputTensor(0).shape}',
    );

    debugPrint(
      'SCREAM: Output shape: '
      '${_interpreter!.getOutputTensor(0).shape}',
    );
  }

  Future<void> startListening({
    required void Function(double probability, bool detected)
        onPrediction,
  }) async {
    if (_isDisposed) {
      throw StateError(
        'ScreamDetectionService has been disposed.',
      );
    }

    if (_isListening) return;

    await initialize();

    _audioSamples.clear();

    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    _isListening = true;

    _audioSubscription = stream.listen(
      (Uint8List chunk) {
        if (!_isListening || _isDisposed) return;

        // Discard audio while muted. Do not retain audio for later.
        if (isSmartMuteActive) {
          _audioSamples.clear();
          return;
        }

        _appendAudioSamples(chunk, onPrediction);
      },
      onError: (Object error) {
        debugPrint('SCREAM AUDIO STREAM ERROR: $error');
      },
      onDone: () {
        _isListening = false;
        _audioSamples.clear();
        debugPrint('SCREAM: Audio stream ended.');
      },
      cancelOnError: false,
    );

    debugPrint('SCREAM: Listening at 16 kHz mono.');
  }

  void _appendAudioSamples(
    Uint8List chunk,
    void Function(double probability, bool detected)
        onPrediction,
  ) {
    // Each PCM16 sample requires two bytes.
    for (int i = 0; i + 1 < chunk.length; i += 2) {
      final raw = chunk[i] | (chunk[i + 1] << 8);
      final signed = raw >= 32768 ? raw - 65536 : raw;

      _audioSamples.add(signed / 32768.0);
    }

    if (_audioSamples.length < windowSamples || _isProcessing) {
      return;
    }

    _isProcessing = true;

    final window = _audioSamples
        .take(windowSamples)
        .toList(growable: false);

    _audioSamples.removeRange(0, windowSamples);

    // Capture the current mute generation. If the mute state changes
    // while inference is running, its result will be discarded.
    final generationAtStart = _muteGeneration;

    unawaited(
      _runPrediction(
        window,
        onPrediction,
        generationAtStart,
      ),
    );
  }

  Future<void> _runPrediction(
    List<double> audio,
    void Function(double probability, bool detected)
        onPrediction,
    int generationAtStart,
  ) async {
    try {
      // Do not begin inference if muted or no longer listening.
      if (!_isListening ||
          _isDisposed ||
          isSmartMuteActive ||
          generationAtStart != _muteGeneration) {
        return;
      }

      final interpreter = _interpreter;
      if (interpreter == null) return;

      debugPrint(
        'SCREAM: Preprocessing 10-second audio window...',
      );

      final processed = _preprocessor.process(audio);

      // Model input shape: [1, 64, 626, 1].
      final input = [processed];
      final output = [
        [0.0]
      ];

      interpreter.run(input, output);

      final probability = output[0][0];
      final detected = probability >= detectionThreshold;

      debugPrint(
        'SCREAM: probability=${probability.toStringAsFixed(4)}, '
        'detected=$detected',
      );

      // Check again after inference. Smart Mute may have been enabled
      // while the model was processing this window.
      if (!_isListening ||
          _isDisposed ||
          isSmartMuteActive ||
          generationAtStart != _muteGeneration) {
        debugPrint(
          'SCREAM: Prediction discarded because monitoring '
          'was muted, stopped, or reset.',
        );
        return;
      }

      onPrediction(probability, detected);
    } catch (error, stackTrace) {
      debugPrint('SCREAM PREDICTION ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _isProcessing = false;

      // If enough fresh audio arrived while inference was running,
      // process the next window when not muted.
      if (_isListening &&
          !_isDisposed &&
          !isSmartMuteActive &&
          _audioSamples.length >= windowSamples) {
        _processNextWindow(onPrediction);
      }
    }
  }

  void _processNextWindow(
    void Function(double probability, bool detected)
        onPrediction,
  ) {
    if (_isProcessing ||
        !_isListening ||
        _isDisposed ||
        isSmartMuteActive ||
        _audioSamples.length < windowSamples) {
      return;
    }

    _isProcessing = true;

    final window = _audioSamples
        .take(windowSamples)
        .toList(growable: false);

    _audioSamples.removeRange(0, windowSamples);

    final generationAtStart = _muteGeneration;

    unawaited(
      _runPrediction(
        window,
        onPrediction,
        generationAtStart,
      ),
    );
  }

  Future<void> stopListening() async {
    _isListening = false;

    // Invalidate any inference already in progress.
    _muteGeneration++;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      if (_recorder != null &&
          await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
    } catch (error) {
      debugPrint('SCREAM: Stop error: $error');
    }

    _audioSamples.clear();
    _isProcessing = false;

    debugPrint('SCREAM: Listening stopped.');
  }

  Future<void> dispose() async {
    if (_isDisposed) return;

    await stopListening();

    _interpreter?.close();
    _interpreter = null;

    await _recorder?.dispose();
    _recorder = null;

    _isDisposed = true;

    debugPrint('SCREAM: Service disposed.');
  }
}
