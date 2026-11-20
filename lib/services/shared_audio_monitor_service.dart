
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

import '../utils/scream_audio_preprocessor.dart';

class SharedAudioMonitorService {
  AudioRecorder? _recorder;

  Model? _voiceModel;
  Recognizer? _recognizer;
  Interpreter? _screamInterpreter;

  StreamSubscription<Uint8List>? _audioSubscription;

  final ScreamAudioPreprocessor _preprocessor =
      ScreamAudioPreprocessor();

  // Ten seconds of mono audio sampled at 16 kHz.
  static const int _windowSamples = 160000;
  static const double _screamThreshold = 0.55;

  static const List<String> _distressPhrases = [
    'help me',
    'save me',
    'emergency',
  ];

  final List<double> _audioSamples = [];

  bool _isListening = false;
  bool _isStarting = false;
  bool _isProcessingScream = false;

  bool _voiceEmergencyTriggered = false;
  bool _screamEmergencyTriggered = false;

  // Keep Vosk audio operations in order.
  Future<void> _voiceProcessingQueue = Future<void>.value();

  // Preserve an incomplete PCM sample between chunks.
  int? _pendingLowByte;

  // Smart Mute expiry, stored as milliseconds since epoch.
  int? _mutedUntilEpochMs;

  // Invalidates queued audio and predictions when mute changes.
  int _muteGeneration = 0;

  bool get isListening => _isListening;

  /// Public getter used by GuardianAlertTaskHandler.
  bool get isSmartMuteActive {
    final until = _mutedUntilEpochMs;

    return until != null &&
        until > DateTime.now().millisecondsSinceEpoch;
  }

  final void Function(String phrase) onVoiceDistressDetected;
  final void Function(double probability) onScreamDetected;

  SharedAudioMonitorService({
    required this.onVoiceDistressDetected,
    required this.onScreamDetected,
  });

  /// Enable Smart Mute until [untilMs].
  ///
  /// Pass null or 0 to disable it immediately.
  /// Fall detection is handled separately and is not affected.
  void setMutedUntilMillis(int? untilMs) {
    if (untilMs == null ||
        untilMs <= DateTime.now().millisecondsSinceEpoch) {
      _mutedUntilEpochMs = null;

      debugPrint(
        'SMART MUTE: Voice and scream detection enabled.',
      );
    } else {
      _mutedUntilEpochMs = untilMs;

      debugPrint(
        'SMART MUTE: Voice and scream detection muted until '
        '${DateTime.fromMillisecondsSinceEpoch(untilMs).toLocal()}.',
      );
    }

    // Invalidate audio work that began before this change.
    _muteGeneration++;

    // Do not classify audio captured before or during mute.
    _audioSamples.clear();
    _pendingLowByte = null;
  }

  Future<void> startListening() async {
    if (_isListening || _isStarting) return;

    _isStarting = true;

    try {
      debugPrint('SHARED AUDIO: Initializing detectors...');

      _recorder ??= AudioRecorder();

      // Microphone permission is requested during onboarding.
      // Let startStream verify whether Android permits recording.
      debugPrint(
        'SHARED AUDIO: Attempting to start microphone stream...',
      );

      // Load the existing Vosk model.
      debugPrint('SHARED AUDIO: Loading Vosk model...');

      final modelPath = await ModelLoader().loadFromAssets(
        'assets/models/vosk-model-small-en-us-0.15.zip',
      );

      _voiceModel =
          await VoskFlutterPlugin.instance().createModel(
        modelPath,
      );

      _recognizer =
          await VoskFlutterPlugin.instance().createRecognizer(
        model: _voiceModel!,
        sampleRate: 16000,
      );

      // Load the existing scream model.
      debugPrint('SHARED AUDIO: Loading scream model...');

      _screamInterpreter = await Interpreter.fromAsset(
        'assets/models/scream_detection_model.tflite',
      );

      debugPrint(
        'SHARED AUDIO: Scream input shape: '
        '${_screamInterpreter!.getInputTensor(0).shape}',
      );

      debugPrint(
        'SHARED AUDIO: Scream output shape: '
        '${_screamInterpreter!.getOutputTensor(0).shape}',
      );

      _audioSamples.clear();
      _pendingLowByte = null;

      _voiceEmergencyTriggered = false;
      _screamEmergencyTriggered = false;
      _isProcessingScream = false;
      _voiceProcessingQueue = Future<void>.value();

      // Open the microphone only once.
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
        _onAudioChunk,
        onError: (Object error) {
          debugPrint('SHARED AUDIO STREAM ERROR: $error');
        },
        onDone: () {
          _isListening = false;
          debugPrint('SHARED AUDIO: Microphone stream ended.');
        },
      );

      debugPrint(
        'SHARED AUDIO: Voice and scream monitoring started.',
      );
    } catch (error, stackTrace) {
      debugPrint('SHARED AUDIO START ERROR: $error');
      debugPrint('$stackTrace');

      await stopListening();
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  void _onAudioChunk(Uint8List chunk) {
    if (!_isListening) return;

    // Discard audio while muted. Do not queue it for recognition.
    if (isSmartMuteActive) {
      _audioSamples.clear();
      _pendingLowByte = null;
      return;
    }

    final generationAtArrival = _muteGeneration;

    // Feed the same microphone bytes to Vosk.
    // Queue processing to prevent overlapping recognizer calls.
    _voiceProcessingQueue = _voiceProcessingQueue
        .then((_) async {
          if (!_isListening ||
              isSmartMuteActive ||
              generationAtArrival != _muteGeneration) {
            return;
          }

          await _processVoiceChunk(
            chunk,
            generationAtArrival,
          );
        })
        .catchError((Object error) {
          debugPrint('VOICE PROCESSING ERROR: $error');
        });

    // Feed the same PCM bytes into the scream pipeline.
    _appendScreamSamples(chunk);
  }

  Future<void> _processVoiceChunk(
    Uint8List chunk,
    int generationAtArrival,
  ) async {
    final recognizer = _recognizer;

    if (!_isListening ||
        recognizer == null ||
        isSmartMuteActive ||
        generationAtArrival != _muteGeneration) {
      return;
    }

    final resultReady =
        await recognizer.acceptWaveformBytes(chunk);

    if (!_isListening ||
        isSmartMuteActive ||
        generationAtArrival != _muteGeneration) {
      return;
    }

    final rawResult = resultReady
        ? await recognizer.getResult()
        : await recognizer.getPartialResult();

    if (!_isListening ||
        isSmartMuteActive ||
        generationAtArrival != _muteGeneration) {
      return;
    }

    _processRecognition(rawResult);
  }

  void _processRecognition(String rawResult) {
    // Final guard in case mute was enabled while recognition ran.
    if (isSmartMuteActive) return;

    try {
      final decoded = jsonDecode(rawResult);

      if (decoded is! Map) return;

      final text = (
        decoded['text'] ?? decoded['partial'] ?? ''
      )
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (text.isEmpty || _voiceEmergencyTriggered) return;

      for (final phrase in _distressPhrases) {
        if (_containsPhrase(text, phrase)) {
          // Check immediately before triggering the callback.
          if (isSmartMuteActive) return;

          _voiceEmergencyTriggered = true;

          debugPrint('VOICE DISTRESS DETECTED: $text');

          onVoiceDistressDetected(phrase);
          return;
        }
      }
    } catch (error) {
      debugPrint('VOICE RESULT PARSE ERROR: $error');
    }
  }

  bool _containsPhrase(String text, String phrase) {
    return (' $text ').contains(' $phrase ');
  }

  void _appendScreamSamples(Uint8List chunk) {
    if (isSmartMuteActive) {
      _audioSamples.clear();
      _pendingLowByte = null;
      return;
    }

    int index = 0;

    // Finish a sample left incomplete by the previous chunk.
    final pending = _pendingLowByte;

    if (pending != null && chunk.isNotEmpty) {
      final raw = pending | (chunk[0] << 8);
      final signed = raw >= 32768 ? raw - 65536 : raw;

      _audioSamples.add(signed / 32768.0);
      _pendingLowByte = null;
      index = 1;
    }

    // PCM signed 16-bit little-endian to [-1, 1].
    for (; index + 1 < chunk.length; index += 2) {
      final raw = chunk[index] | (chunk[index + 1] << 8);
      final signed = raw >= 32768 ? raw - 65536 : raw;

      _audioSamples.add(signed / 32768.0);
    }

    // Keep an odd final byte for the next chunk.
    if (index < chunk.length) {
      _pendingLowByte = chunk[index];
    }

    _processAvailableScreamWindows();
  }

  void _processAvailableScreamWindows() {
    if (!_isListening ||
        _isProcessingScream ||
        isSmartMuteActive) {
      if (isSmartMuteActive) {
        _audioSamples.clear();
        _pendingLowByte = null;
      }
      return;
    }

    if (_audioSamples.length < _windowSamples) return;

    final interpreter = _screamInterpreter;

    if (interpreter == null) return;

    _isProcessingScream = true;

    // Capture the generation so a later mute change invalidates
    // the result of this prediction.
    final generationAtStart = _muteGeneration;

    // Copy and remove exactly one 10-second window.
    final window = _audioSamples
        .take(_windowSamples)
        .toList(growable: false);

    _audioSamples.removeRange(0, _windowSamples);

    unawaited(
      _runScreamPrediction(
        window,
        generationAtStart,
      ),
    );
  }

  Future<void> _runScreamPrediction(
    List<double> audio,
    int generationAtStart,
  ) async {
    try {
      if (!_isListening ||
          isSmartMuteActive ||
          generationAtStart != _muteGeneration) {
        return;
      }

      final interpreter = _screamInterpreter;

      if (interpreter == null) return;

      debugPrint(
        'SCREAM: Processing 10-second audio window...',
      );

      // Preserve the existing preprocessing.
      // Shape: [64, 626, 1].
      final processed = _preprocessor.process(audio);

      // Model input shape: [1, 64, 626, 1].
      final input = [processed];
      final output = [
        [0.0],
      ];

      interpreter.run(input, output);

      final probability = output[0][0];
      final detected = probability >= _screamThreshold;

      debugPrint(
        'SCREAM: probability='
        '${probability.toStringAsFixed(4)}, '
        'detected=$detected',
      );

      // Re-check after inference. Smart Mute may have been enabled
      // while preprocessing or inference was running.
      if (!_isListening ||
          isSmartMuteActive ||
          generationAtStart != _muteGeneration) {
        debugPrint(
          'SCREAM: Prediction discarded because Smart Mute '
          'changed or monitoring stopped.',
        );
        return;
      }

      if (detected && !_screamEmergencyTriggered) {
        // Last check immediately before the callback.
        if (isSmartMuteActive ||
            generationAtStart != _muteGeneration) {
          return;
        }

        _screamEmergencyTriggered = true;

        debugPrint('SCREAM EMERGENCY DETECTED');

        onScreamDetected(probability);
      }
    } catch (error, stackTrace) {
      debugPrint('SCREAM PREDICTION ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _isProcessingScream = false;

      // Process another complete window if one accumulated
      // while the model was running, provided mute is inactive.
      if (_isListening &&
          !isSmartMuteActive &&
          _audioSamples.length >= _windowSamples) {
        _processAvailableScreamWindows();
      }
    }
  }

  void resetEmergencyTriggers() {
    _voiceEmergencyTriggered = false;
    _screamEmergencyTriggered = false;

    debugPrint(
      'SHARED AUDIO: Emergency trigger flags reset.',
    );
  }

  Future<void> stopListening() async {
    _isListening = false;

    // Invalidate any outstanding audio processing.
    _muteGeneration++;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      if (_recorder != null &&
          await _recorder!.isRecording()) {
        await _recorder!.stop();
      }
    } catch (error) {
      debugPrint('SHARED AUDIO STOP ERROR: $error');
    }

    // Wait for queued Vosk calls before disposing its recognizer.
    try {
      await _voiceProcessingQueue;
    } catch (error) {
      debugPrint('VOICE QUEUE STOP ERROR: $error');
    }

    _recognizer?.dispose();
    _recognizer = null;

    _voiceModel?.dispose();
    _voiceModel = null;

    _screamInterpreter?.close();
    _screamInterpreter = null;

    _audioSamples.clear();
    _pendingLowByte = null;

    _voiceEmergencyTriggered = false;
    _screamEmergencyTriggered = false;
    _isProcessingScream = false;

    debugPrint('SHARED AUDIO: Monitoring stopped.');
  }

  Future<void> dispose() async {
    await stopListening();

    await _recorder?.dispose();
    _recorder = null;
  }
}
