
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/emergency_alert.dart';

class FirestoreEmergencyService {
  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

    
  static Future<String> getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('User must be signed in.');
    }

    final document = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();

    if (!document.exists) {
      throw StateError('User profile was not found in Firestore.');
    }

    final data = document.data()!;
    final name = data['name'];

    if (name is! String || name.trim().isEmpty) {
      throw StateError('User name is missing from the profile.');
    }

    return name.trim();
  }

  static Future<String> saveEmergencyAlert(
    EmergencyAlert alert, {
    required String userName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('User must be signed in to save an emergency alert.');
    }

    final document = await _firestore
        .collection('emergency_alerts')
        .add({
      'userId': user.uid,
      'userName': userName,
      'alertType': alert.alertType,
      'latitude': alert.latitude,
      'longitude': alert.longitude,
      'status': alert.status,
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('FIRESTORE: Emergency alert saved: ${document.id}');

    return document.id;
  }

  static Future<void> updateEmergencyAlertLocation({required String alertId,required double latitude,required double longitude,}) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
        throw StateError('User must be signed in.');
    }

    await _firestore
        .collection('emergency_alerts')
        .doc(alertId)
        .update({
      'latitude': latitude,
      'longitude': longitude,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    });

    print('FIRESTORE: Alert location updated: $alertId');
  }

  
  static Future<void> updateEmergencyAlertStatus({required String alertId,required String status,}) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('User must be signed in.');
    }

    if (!['pending', 'cancelled', 'triggered'].contains(status)) {
      throw ArgumentError('Invalid emergency alert status.');
    }

    await _firestore
        .collection('emergency_alerts')
        .doc(alertId)
        .update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    print('FIRESTORE: Alert $alertId updated to $status.');
  }

}
