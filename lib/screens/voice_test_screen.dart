
import 'package:flutter/material.dart';

import '../services/scream_detection_service.dart';

class VoiceTestScreen extends StatefulWidget {
  const VoiceTestScreen({super.key});

  @override
  State<VoiceTestScreen> createState() => _VoiceTestScreenState();
}

class _VoiceTestScreenState extends State<VoiceTestScreen> {
  late final ScreamDetectionService _screamService;

  String _status = 'Ready to test scream detection';
  String _probabilityText = 'Waiting for audio analysis';
  bool _isListening = false;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _screamService = ScreamDetectionService();
  }

  Future<void> _startTest() async {
    if (_isStarting || _isListening) return;

    setState(() {
      _isStarting = true;
      _status = 'Starting microphone...';
      _probabilityText = 'Collecting 10 seconds of audio';
    });

    try {
      await _screamService.startListening(
        onPrediction: (double probability, bool detected) {
          if (!mounted) return;

          setState(() {
            _status = detected
                ? 'SCREAMING DETECTED'
                : 'NO SCREAMING DETECTED';

            _probabilityText =
                'Scream probability: '
                '${(probability * 100).toStringAsFixed(1)}%';
          });
        },
      );

      if (!mounted) return;

      setState(() {
        _isListening = _screamService.isListening;
        _status = 'Listening — collecting audio...';
      });
    } catch (error, stackTrace) {
      debugPrint('SCREAM TEST ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _status = 'Could not start: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stopTest() async {
    await _screamService.stopListening();

    if (!mounted) return;

    setState(() {
      _isListening = false;
      _status = 'Test stopped';
      _probabilityText = 'Start again to analyse another audio window';
    });
  }

  @override
  void dispose() {
    _screamService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scream Detection Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.graphic_eq, size: 64),
            const SizedBox(height: 24),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _probabilityText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: (_isListening || _isStarting)
                  ? null
                  : _startTest,
              child: Text(
                _isStarting ? 'Starting...' : 'Start Scream Detection',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isListening ? _stopTest : null,
              child: const Text('Stop Test'),
            ),
            const Spacer(),
            const Text(
              'Analysis runs on 10-second audio windows. '
              'Results are experimental and do not trigger emergency alerts.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
