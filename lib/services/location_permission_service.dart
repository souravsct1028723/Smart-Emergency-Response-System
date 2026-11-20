
import 'package:geolocator/geolocator.dart';

class LocationPermissionService {
  static Future<bool> requestLocationPermissions() async {
    // Check whether device location is enabled.
    final serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    // Request foreground location permission first.
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    // Background updates require "Allow all the time"
    // on supported Android versions.
    if (permission != LocationPermission.always) {
      return false;
    }

    return true;
  }
}
