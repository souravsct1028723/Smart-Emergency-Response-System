
import 'dart:math';

import '../models/nearby_user.dart';

class NearbyUserService {
  /// Calculates the distance between two GPS coordinates in metres.
  static double calculateDistanceMetres({
    required double latitude1,
    required double longitude1,
    required double latitude2,
    required double longitude2,
  }) {
    const earthRadiusMetres = 6371000.0;

    final lat1 = latitude1 * pi / 180;
    final lat2 = latitude2 * pi / 180;
    final deltaLat = (latitude2 - latitude1) * pi / 180;
    final deltaLon = (longitude2 - longitude1) * pi / 180;

    final a = pow(sin(deltaLat / 2), 2) +
        cos(lat1) *
            cos(lat2) *
            pow(sin(deltaLon / 2), 2);

    final boundedA = a.clamp(0.0, 1.0);
    final centralAngle =
        2 * atan2(sqrt(boundedA), sqrt(1 - boundedA));

    return earthRadiusMetres * centralAngle;
  }

  /// Returns true when a user is within the specified radius.
  static bool isWithinRadius({
    required double emergencyLatitude,
    required double emergencyLongitude,
    required double userLatitude,
    required double userLongitude,
    double radiusMetres = 5000,
  }) {
    final distance = calculateDistanceMetres(
      latitude1: emergencyLatitude,
      longitude1: emergencyLongitude,
      latitude2: userLatitude,
      longitude2: userLongitude,
    );

    return distance <= radiusMetres;
  }
  
  /// Filters candidate users to those within 5 km,
  /// excluding the person who triggered the emergency.
  static List<NearbyUser> findUsersWithinRadius({
    required double emergencyLatitude,
    required double emergencyLongitude,
    required String emergencyUserId,
    required List<NearbyUser> candidates,
    double radiusMetres = 5000,
  }) {
    return candidates.where((user) {
      if (user.uid == emergencyUserId) {
        return false;
      }

      return isWithinRadius(
        emergencyLatitude: emergencyLatitude,
        emergencyLongitude: emergencyLongitude,
        userLatitude: user.latitude,
        userLongitude: user.longitude,
        radiusMetres: radiusMetres,
      );
    }).toList();
  }
}
