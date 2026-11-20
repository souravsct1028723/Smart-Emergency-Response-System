
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

class VoiceEmergencyService {
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;

  StreamSubscription<String>? _resultSubscription;
  StreamSubscription<String>? _partialSubscription;

  bool _isListening = false;
  bool _emergencyTriggered = false;

  final void Function(String phrase) onDistressDetected;

  VoiceEmergencyService({
    required this.onDistressDetected,
  });

  static const List<String> _distressPhrases = [
    'help me',
    'save me',
    'emergency',
  ];

  Future<void> startListening() async {
    if (_isListening) return;

    _emergencyTriggered = false;

    try {
      debugPrint('VOICE: Loading Vosk model...');

      final modelPath = await ModelLoader().loadFromAssets(
        'assets/models/vosk-model-small-en-us-0.15.zip',
      );

      _model = await VoskFlutterPlugin.instance().createModel(modelPath);

      _recognizer =
          await VoskFlutterPlugin.instance().createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );

      _speechService =
          await VoskFlutterPlugin.instance().initSpeechService(
        _recognizer!,
      );

      _resultSubscription = _speechService!.onResult().listen(
        _processRecognition,
        onError: (Object error) {
          debugPrint('VOICE RESULT ERROR: $error');
        },
      );

      _partialSubscription = _speechService!.onPartial().listen(
        _processRecognition,
        onError: (Object error) {
          debugPrint('VOICE PARTIAL ERROR: $error');
        },
      );

      await _speechService!.start();
      _isListening = true;

      debugPrint('VOICE: Listening started.');
    } catch (error, stackTrace) {
      debugPrint('VOICE START ERROR: $error');
      debugPrint('$stackTrace');
      await stopListening();
      rethrow;
    }
  }

  void _processRecognition(String rawResult) {
    try {
      final decoded = jsonDecode(rawResult);

      if (decoded is! Map) return;

      final text = (decoded['text'] ?? decoded['partial'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (text.isEmpty || _emergencyTriggered) return;

      for (final phrase in _distressPhrases) {
        if (_containsPhrase(text, phrase)) {
          _emergencyTriggered = true;

          debugPrint('VOICE DISTRESS DETECTED: $text');

          onDistressDetected(phrase);
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

  Future<void> stopListening() async {
    await _resultSubscription?.cancel();
    _resultSubscription = null;

    await _partialSubscription?.cancel();
    _partialSubscription = null;

    try {
      await _speechService?.stop();
      await _speechService?.dispose();
    } catch (error) {
      debugPrint('VOICE STOP ERROR: $error');
    }

    _speechService = null;

    _recognizer?.dispose();
    _recognizer = null;

    _model?.dispose();
    _model = null;

    _isListening = false;
    debugPrint('VOICE: Listening stopped.');
    _emergencyTriggered = false;
  }

  Future<void> dispose() async {
    await stopListening();
  }
}
