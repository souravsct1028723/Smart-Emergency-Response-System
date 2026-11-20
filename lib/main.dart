import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/welcome_screen.dart';
import 'services/emergency_manager.dart';
import 'services/guardian_alert_task.dart';
import 'services/notification_service.dart';
import 'services/background_location_service.dart';
import 'screens/home_screen.dart';

import 'navigation/app_navigator.dart';

import 'screens/voice_test_screen.dart';



Future<void> _onReceiveTaskData(Object data) async {
  debugPrint('FOREGROUND SERVICE DATA: $data');

  if (data is! Map) return;

  final type = data['type'];

  if (type != 'fall_confirmed' &&
      type != 'voice_emergency_detected' &&
      type != 'scream_emergency_detected') {
    return;
  }

  debugPrint('MAIN APP: Emergency event received: $type');

  // Notify the existing HomeScreen workflow.
  switch (type) {
    case 'fall_confirmed':
      EmergencyManager.notifyFallConfirmed();
      break;

    case 'voice_emergency_detected':
      EmergencyManager.notifyVoiceEmergencyDetected();
      break;

    case 'scream_emergency_detected':
      EmergencyManager.notifyScreamEmergencyDetected();
      break;
  }

  // Request Android to display the emergency notification.
  try {
    await NotificationService.showEmergencyCountdown();
    debugPrint('MAIN APP: Emergency notification requested.');
  } catch (e, stackTrace) {
    debugPrint('MAIN APP: Failed to show emergency notification: $e');
    debugPrint('$stackTrace');
  }
}



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print('FIREBASE: Initialized successfully.');
  await BackgroundLocationService.initialize();
  print('BACKGROUND LOCATION: Workmanager initialized.');
  print(
    'FIREBASE AUTH: Current user = '
    '${FirebaseAuth.instance.currentUser?.uid ?? "Not signed in"}',
  );

  await NotificationService.initialize();
  
  FlutterForegroundTask.initCommunicationPort();

  FlutterForegroundTask.addTaskDataCallback(
    _onReceiveTaskData,
  );

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'guardian_alert_channel',
      channelName: 'Guardian Alert',
      channelDescription: 'Background emergency monitoring',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,  
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
    ),
  );

  runApp(const GuardianAlertApp());

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final isGuardianEmergency =
        NotificationService.consumePendingGuardianEmergency();

    if (isGuardianEmergency) {
      debugPrint(
        'MAIN APP: Guardian emergency launch detected.',
      );

      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomeScreen(
            startEmergencyOnOpen: true,
          ),
        ),
      );
    } else {
      NotificationService.handlePendingNotification();
    }
  });

}

class GuardianAlertApp extends StatelessWidget {
  const GuardianAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Guardian Alert',
      theme: ThemeData(
        primarySwatch: Colors.red,
        fontFamily: 'Roboto',
      ),
      home: const WelcomeScreen(),
    );
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(
    GuardianAlertTaskHandler(),
  );
}



Future<void> startGuardianService({
  bool enableMicrophone = false,
}) async {
  try {
    final isRunning = await FlutterForegroundTask.isRunningService;

    if (isRunning) {
      if (!enableMicrophone) {
        print('FOREGROUND SERVICE: Already running.');
        return;
      }

      // Restart so the service starts with microphone support.
      await FlutterForegroundTask.stopService();
    }

    final serviceTypes = <ForegroundServiceTypes>[
      ForegroundServiceTypes.location,
      if (enableMicrophone)
        ForegroundServiceTypes.microphone,
    ];

    await FlutterForegroundTask.startService(
      serviceTypes: serviceTypes,
      notificationTitle: 'Guardian Alert',
      notificationText: enableMicrophone
          ? 'Fall and voice monitoring are active'
          : 'Fall monitoring is active',
      callback: startCallback,
    );

    print(
      'FOREGROUND SERVICE: Started. '
      'Microphone enabled: $enableMicrophone',
    );
  } catch (e, stackTrace) {
    print('FOREGROUND SERVICE ERROR: $e');
    print(stackTrace);
  }
}
