
import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fall_detection_service.dart';
import 'shared_audio_monitor_service.dart';

class GuardianAlertTaskHandler extends TaskHandler {
  FallDetectionService? _fallDetectionService;
  SharedAudioMonitorService? _audioMonitorService;

  StreamSubscription<AccelerometerEvent>?
      _accelerometerSubscription;

  final List<List<double>> _sensorWindow = [];

  static const int windowSize = 151;
  static const int windowStride = 50;

  static const double fallThreshold = 0.5;
  static const int requiredFallPredictions = 3;

  static const String _smartMuteKey = 'smartMuteUntilEpochMs';

  int _samplesSinceLastInference = 0;
  int _consecutiveFallCount = 0;

  bool _isStopping = false;

  final FlutterLocalNotificationsPlugin _taskNotifications =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(
    DateTime timestamp,
    TaskStarter starter,
  ) async {
    print('FOREGROUND SERVICE: Started');

    try {
      await _taskNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(
            '@mipmap/ic_launcher',
          ),
        ),
      );

      print(
        'FOREGROUND SERVICE: Emergency notifier initialized',
      );

      // Restore Smart Mute before starting audio monitoring.
      final prefs = await SharedPreferences.getInstance();
      final savedUntil = prefs.getInt(_smartMuteKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      int? activeMuteUntil;

      if (savedUntil != null && savedUntil > now) {
        activeMuteUntil = savedUntil;

        print(
          'FOREGROUND SERVICE: Smart Mute restored until '
          '${DateTime.fromMillisecondsSinceEpoch(savedUntil)}',
        );
      } else {
        // Remove an expired or invalid saved mute.
        if (savedUntil != null) {
          await prefs.remove(_smartMuteKey);
        }

        print(
          'FOREGROUND SERVICE: Smart Mute is not active.',
        );
      }

      // Keep the existing fall-detection initialization unchanged.
      _fallDetectionService = FallDetectionService();
      await _fallDetectionService!.loadModel();

      print('FOREGROUND SERVICE: Fall model ready');

      _startAccelerometerMonitoring();

      // Start voice and scream monitoring using one shared
      // microphone stream.
      _audioMonitorService = SharedAudioMonitorService(
        onVoiceDistressDetected: (phrase) {
          if (_isStopping) return;

          // Extra safety check: never send audio alerts while muted.
          if (_audioMonitorService?.isSmartMuteActive == true) {
            print(
              'FOREGROUND SERVICE: Voice alert suppressed '
              'because Smart Mute is active.',
            );
            return;
          }

          print(
            'FOREGROUND SERVICE: Voice distress detected: '
            '$phrase',
          );

          unawaited(_showEmergencyNotificationFromTask());

          FlutterForegroundTask.sendDataToMain({
            'type': 'voice_emergency_detected',
            'phrase': phrase,
            'timestamp':
                DateTime.now().millisecondsSinceEpoch,
          });
        },
        onScreamDetected: (probability) {
          if (_isStopping) return;

          // Extra safety check: never send scream alerts while muted.
          if (_audioMonitorService?.isSmartMuteActive == true) {
            print(
              'FOREGROUND SERVICE: Scream alert suppressed '
              'because Smart Mute is active.',
            );
            return;
          }

          print(
            'FOREGROUND SERVICE: Scream detected. '
            'Probability: $probability',
          );

          unawaited(_showEmergencyNotificationFromTask());

          FlutterForegroundTask.sendDataToMain({
            'type': 'scream_emergency_detected',
            'probability': probability,
            'timestamp':
                DateTime.now().millisecondsSinceEpoch,
          });
        },
      );

      // Apply the restored expiry before audio listening begins.
      _audioMonitorService!.setMutedUntilMillis(
        activeMuteUntil,
      );

      await _audioMonitorService!.startListening();

      print(
        'FOREGROUND SERVICE: Fall, voice, and scream '
        'monitoring initialized.',
      );
    } catch (error, stackTrace) {
      print('FOREGROUND SERVICE START ERROR: $error');
      print(stackTrace);
    }
  }

  void _startAccelerometerMonitoring() {
    print(
      'FOREGROUND SERVICE: Starting accelerometer...',
    );

    _accelerometerSubscription =
        accelerometerEventStream().listen(
      (event) {
        if (_isStopping) return;

        _sensorWindow.add([
          event.x,
          event.y,
          event.z,
        ]);

        if (_sensorWindow.length > windowSize) {
          _sensorWindow.removeAt(0);
        }

        _samplesSinceLastInference++;

        // Preserve the existing fall-detection logic.
        // Smart Mute must never disable fall detection.
        if (_sensorWindow.length < windowSize) {
          return;
        }

        if (_samplesSinceLastInference < windowStride) {
          return;
        }

        _samplesSinceLastInference = 0;

        final window = List<List<double>>.from(
          _sensorWindow.map(
            (sample) => List<double>.from(sample),
          ),
        );

        _runFallDetection(window);
      },
      onError: (error) {
        print(
          'FOREGROUND ACCELEROMETER ERROR: $error',
        );
      },
    );
  }

  void _runFallDetection(
    List<List<double>> window,
  ) {
    try {
      final service = _fallDetectionService;
      if (service == null || _isStopping) return;

      final probability = service.predict(window);

      if (probability >= fallThreshold) {
        _consecutiveFallCount++;

        print(
          'FOREGROUND FALL DETECTION: '
          'Probability = $probability | '
          'FALL | '
          'Consecutive = $_consecutiveFallCount',
        );

        if (_consecutiveFallCount >=
            requiredFallPredictions) {
          print('FOREGROUND FALL CONFIRMED!');

          _consecutiveFallCount = 0;
          _sendFallConfirmed();
        }
      } else {
        _consecutiveFallCount = 0;

        print(
          'FOREGROUND FALL DETECTION: '
          'Probability = $probability | NORMAL',
        );
      }
    } catch (error) {
      print(
        'FOREGROUND FALL DETECTION ERROR: $error',
      );
    }
  }

  void _sendFallConfirmed() {
    if (_isStopping) return;

    print(
      'FOREGROUND SERVICE: Sending fall confirmation '
      'to main app.',
    );

    unawaited(_showEmergencyNotificationFromTask());

    FlutterForegroundTask.sendDataToMain({
      'type': 'fall_confirmed',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    print('FOREGROUND SERVICE: Running');
  }

  @override
  Future<void> onDestroy(
    DateTime timestamp,
    bool isTimeout,
  ) async {
    _isStopping = true;

    print('FOREGROUND SERVICE: Stopping');

    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;

    await _audioMonitorService?.dispose();
    _audioMonitorService = null;

    _fallDetectionService?.dispose();
    _fallDetectionService = null;

    _sensorWindow.clear();
    _samplesSinceLastInference = 0;
    _consecutiveFallCount = 0;

    print('FOREGROUND SERVICE: Stopped');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print(
      'FOREGROUND SERVICE: '
      'Notification button pressed: $id',
    );
  }

  @override
  void onNotificationPressed() {
    print('FOREGROUND SERVICE: Notification pressed');
  }

  @override
  void onNotificationDismissed() {
    print('FOREGROUND SERVICE: Notification dismissed');
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    if (data['type'] == 'reset_emergency_triggers') {
      _audioMonitorService?.resetEmergencyTriggers();

      print(
        'FOREGROUND SERVICE: Audio emergency triggers reset.',
      );

      return;
    }

    if (data['type'] == 'smart_mute_until') {
      final value = data['until'];

      final int? untilMs =
          value is int ? value : null;

      final int? activeUntil =
          untilMs != null &&
                  untilMs >
                      DateTime.now().millisecondsSinceEpoch
              ? untilMs
              : null;

      // Apply the new mute state immediately to the audio service.
      _audioMonitorService?.setMutedUntilMillis(
        activeUntil,
      );

      // Persist the value so it survives foreground-task restarts.
      unawaited(_saveSmartMuteExpiry(activeUntil));

      print(
        activeUntil == null
            ? 'FOREGROUND SERVICE: Smart Mute disabled.'
            : 'FOREGROUND SERVICE: Smart Mute updated until '
                '${DateTime.fromMillisecondsSinceEpoch(activeUntil)}',
      );
    }
  }

  Future<void> _saveSmartMuteExpiry(int? untilMs) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (untilMs == null) {
        await prefs.remove(_smartMuteKey);
      } else {
        await prefs.setInt(_smartMuteKey, untilMs);
      }
    } catch (error) {
      print(
        'FOREGROUND SERVICE: Could not save Smart Mute: $error',
      );
    }
  }

  Future<void> _showEmergencyNotificationFromTask() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'emergency_alert_channel',
        'Emergency Alerts',
        channelDescription:
            'Emergency alerts from Guardian Alert',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        ongoing: true,
        autoCancel: false,
      );

      await _taskNotifications.show(
        id: 1001,
        title: '🚨 Emergency Detected',
        body:
            'Emergency countdown started — 30 seconds to cancel',
        notificationDetails: const NotificationDetails(
          android: androidDetails,
        ),
        payload: '{"type":"guardian_emergency"}',
      );

      print(
        'FOREGROUND SERVICE: Emergency notification posted',
      );
    } catch (error, stackTrace) {
      print(
        'FOREGROUND SERVICE: Notification failed: $error',
      );
      print(stackTrace);
    }
  }
}
