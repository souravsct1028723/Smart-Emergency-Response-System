
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void backgroundLocationCallback() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint(
          'BACKGROUND LOCATION: Location services are disabled.',
        );
        return false;
      }

      final permission = await Geolocator.checkPermission();

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        debugPrint(
          'BACKGROUND LOCATION: Location permission unavailable: $permission',
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      debugPrint(
        'BACKGROUND LOCATION: '
        '${position.latitude}, ${position.longitude}',
      );

      return true;
    } catch (e) {
      debugPrint('BACKGROUND LOCATION ERROR: $e');
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


class LocationService {
  static Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('LOCATION: Location services are disabled.');
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('LOCATION: Permission denied: $permission');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint('LOCATION ERROR: $e');
      return null;
    }
  }
}

