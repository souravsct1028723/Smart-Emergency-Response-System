
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_alert/services/nearby_user_service.dart';
import 'package:guardian_alert/models/nearby_user.dart';

void main() {
  group('NearbyUserService — 5 km radius', () {
    test('Same coordinates are within 5 km', () {
      expect(
        NearbyUserService.isWithinRadius(
          emergencyLatitude: 9.3331,
          emergencyLongitude: 76.3760,
          userLatitude: 9.3331,
          userLongitude: 76.3760,
        ),
        isTrue,
      );
    });

    test('Location approximately 3 km away is within 5 km', () {
      expect(
        NearbyUserService.isWithinRadius(
          emergencyLatitude: 0,
          emergencyLongitude: 0,
          userLatitude: 0,
          userLongitude: 0.027,
        ),
        isTrue,
      );
    });

    test('Location approximately 6 km away is outside 5 km', () {
      expect(
        NearbyUserService.isWithinRadius(
          emergencyLatitude: 0,
          emergencyLongitude: 0,
          userLatitude: 0,
          userLongitude: 0.054,
        ),
        isFalse,
      );
    });
  });

  group('findUsersWithinRadius', () {
    test('excludes the emergency sender and users outside 5 km', () {
        final candidates = [
            const NearbyUser(
                uid: 'emergency_sender',
                latitude: 9.3331,
                longitude: 76.3760,
            ),
            const NearbyUser(
                uid: 'nearby_user',
                latitude: 9.3431,
                longitude: 76.3760,
            ),
            const NearbyUser(
                uid: 'far_user',
                latitude: 9.4000,
                longitude: 76.3760,
            ),
        ];

        final result = NearbyUserService.findUsersWithinRadius(
            emergencyLatitude: 9.3331,
            emergencyLongitude: 76.3760,
            emergencyUserId: 'emergency_sender',
            candidates: candidates,
        );

        expect(result.map((user) => user.uid).toList(), ['nearby_user']);
    });
  });
}
