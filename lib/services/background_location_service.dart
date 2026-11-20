
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

import 'nearby_location_firestore_service.dart';

@pragma('vm:entry-point')

@pragma('vm:entry-point')

@pragma('vm:entry-point')
void backgroundLocationCallback() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
    );

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        print('BACKGROUND LOCATION: GPS is disabled.');
        return true;
      }

      final permission = await Geolocator.checkPermission();

      if (permission != LocationPermission.always) {
        print('BACKGROUND LOCATION: Always permission required.');
        return true;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      print(
        'BACKGROUND LOCATION: '
        '${position.latitude}, ${position.longitude}',
      );

      await NearbyLocationFirestoreService.saveUserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      print('BACKGROUND LOCATION: Saved to Firestore.');

      return true;
    } catch (e, stackTrace) {
      print('BACKGROUND LOCATION ERROR: $e');
      print(stackTrace);
      return false;
    }
  });
}

class BackgroundLocationService {
  static const String locationTaskName = 'refreshUserLocation';

  static Future<void> initialize() async {
    await Workmanager().initialize(
      backgroundLocationCallback,
    );
  }

  static Future<void> scheduleLocationUpdates() async {
    await Workmanager().registerPeriodicTask(
      'guardian-alert-location-refresh',
      locationTaskName,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> cancelLocationUpdates() async {
    await Workmanager().cancelByUniqueName(
      'guardian-alert-location-refresh',
    );
  }
}
