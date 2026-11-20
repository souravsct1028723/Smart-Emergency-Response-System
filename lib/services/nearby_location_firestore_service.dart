
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NearbyLocationFirestoreService {
  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  static Future<void> saveUserLocation({
    required double latitude,
    required double longitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User is not signed in.');
    }

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid GPS coordinates.');
    }

    await _firestore
        .collection('user_locations')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  
  /// Saves whether the signed-in user consents to nearby alerts.
  static Future<void> saveNearbyAlertConsent({
    required bool enabled,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('User is not signed in.');
    }

    await _firestore
        .collection('user_locations')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'nearbyAlertsEnabled': enabled,
      'consentUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
