
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../navigation/app_navigator.dart';
import '../screens/emergency_details_screen.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static final FirebaseMessaging _messaging =
      FirebaseMessaging.instance;

  static Map<String, dynamic>? _pendingAlertData;

  static bool _pendingGuardianEmergency = false;

  static bool consumePendingGuardianEmergency() {
    final pending = _pendingGuardianEmergency;
    _pendingGuardianEmergency = false;
    return pending;
  }

  static Future<String?> initializeFirebaseMessaging() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint(
      'FCM: Notification permission = '
      '${settings.authorizationStatus}',
    );

    final token = await _messaging.getToken();

    if (token != null) {
      debugPrint('FCM: Device token retrieved successfully.');
    } else {
      debugPrint('FCM: Device token is not available yet.');
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await saveFcmToken(newToken);
      } catch (e) {
        debugPrint('FCM TOKEN REFRESH ERROR: $e');
      }
    });

    return token;
  }

  static Future<void> saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('FCM: Token not saved because no user is signed in.');
      return;
    }

    await FirebaseFirestore.instance
        .collection('fcm_tokens')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('FCM: Device token registered successfully.');
  }

  static const AndroidNotificationChannel emergencyChannel =
      AndroidNotificationChannel(
    'emergency_alert_channel',
    'Emergency Alerts',
    description: 'Emergency alerts from Guardian Alert',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(emergencyChannel);

    // Handle a local notification that launched the app.
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload =
          launchDetails?.notificationResponse?.payload;

      if (payload != null) {
        _queueLocalNotificationPayload(payload);
      }
    }

    debugPrint('NOTIFICATION SERVICE: Initialized');

    await initializeFirebaseMessaging();

    // Notification received while the app is open.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;

      if (notification == null) return;

      final payloadData = <String, dynamic>{
        ...message.data,
        'title': notification.title ?? 'Nearby Emergency Alert',
        'body': notification.body ??
            'An emergency has been reported nearby.',
      };

      await _notifications.show(
        id: message.messageId.hashCode,
        title: notification.title ?? 'Nearby Emergency Alert',
        body: notification.body ??
            'An emergency has been reported nearby.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'emergency_alert_channel',
            'Emergency Alerts',
            channelDescription: 'Emergency alerts from Guardian Alert',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
          ),
        ),
        payload: jsonEncode(payloadData),
      );

      debugPrint('FCM: Incoming notification displayed.');
    });

    // Notification tapped while the app was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationData(message.data);
    });

    // Notification tapped when the app was terminated.
    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      _pendingAlertData = Map<String, dynamic>.from(
        initialMessage.data,
      );
    }
  }
  
  static bool _isOpeningEmergency = false;
  static bool _navigationRetryScheduled = false;

  static void handlePendingNotification() {
    if (_isOpeningEmergency) return;

    final data = _pendingAlertData;
    if (data == null) {
      debugPrint('NOTIFICATION: No pending notification.');
      return;
    }

    final alertId = data['alertId']?.toString();
    if (alertId == null || alertId.isEmpty) {
      debugPrint('NOTIFICATION: Pending alert has no alertId.');
      _pendingAlertData = null;
      return;
    }

    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      debugPrint(
        'NOTIFICATION: Navigator is not ready; waiting for first frame.',
      );

      if (_navigationRetryScheduled) return;
      _navigationRetryScheduled = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigationRetryScheduled = false;
        handlePendingNotification();
      });

      return;
    }

    _isOpeningEmergency = true;
    _pendingAlertData = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentNavigator = navigatorKey.currentState;

      if (currentNavigator == null) {
        _pendingAlertData = data;
        _isOpeningEmergency = false;
        debugPrint(
          'NOTIFICATION: Navigator unavailable; alert retained.',
        );
        return;
      }

      debugPrint('NOTIFICATION: Opening emergency $alertId');

      currentNavigator
          .push(
        MaterialPageRoute(
          builder: (_) => EmergencyDetailsScreen(
            alertData: data,
          ),
        ),
      )
      .whenComplete(() {
        _isOpeningEmergency = false;
      });
    });
  }

  static void _queueLocalNotificationPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);

      if (decoded is! Map) return;

      final data = Map<String, dynamic>.from(decoded);

      if (data['type'] == 'guardian_emergency') {
        _pendingGuardianEmergency = true;
        debugPrint(
          'NOTIFICATION: Full-screen emergency launch detected.',
        );
        return;
      }

      _pendingAlertData = data;
    } catch (e) {
      debugPrint('NOTIFICATION: Invalid payload: $e');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint(
      'NOTIFICATION SERVICE: Notification tapped: ${response.id}',
    );

    if (response.id == 1001) {
      _pendingGuardianEmergency = true;

      debugPrint(
        'NOTIFICATION SERVICE: Guardian emergency launch recognized.',
      );
      return;
    }

    final payload = response.payload;

    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);

      if (decoded is Map) {
        _handleNotificationData(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (e) {
      debugPrint('NOTIFICATION: Could not process tap: $e');
    }
  }

  static void _handleNotificationData(
    Map<String, dynamic> data,
  ) {
    if (data['type'] != 'nearby_emergency') {
      debugPrint('NOTIFICATION: Not a nearby emergency alert.');
      return;
    }

    _openEmergencyDetails(data);
  }

  
  static void _openEmergencyDetails(
    Map<String, dynamic> data,
  ) {
    final alertId = data['alertId']?.toString();

    if (alertId == null || alertId.isEmpty) {
      debugPrint('NOTIFICATION: Missing alertId.');
      return;
    }

    _pendingAlertData = data;

    debugPrint(
      'NOTIFICATION: Queued emergency $alertId for navigation.',
    );

    handlePendingNotification();
  }

  static Future<void> showEmergencyCountdown() async {
    const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
        'emergency_alert_channel',
      'Emergency Alerts',
      channelDescription: 'Emergency alerts from Guardian Alert',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      id: 1001,
      title: '🚨 Emergency Detected',
      body: 'Emergency countdown started — 30 seconds to cancel',
      notificationDetails: details,
      payload: jsonEncode({
        'type': 'guardian_emergency',
      }),
    );

    debugPrint('NOTIFICATION SERVICE: Emergency notification shown');
  }

  static Future<void> cancelEmergencyNotification() async {
    await _notifications.cancel(id: 1001);

    debugPrint(
      'NOTIFICATION SERVICE: Emergency notification cancelled',
    );
  }
}
