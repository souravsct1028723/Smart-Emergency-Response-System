
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class NearbyAlertService {
  
  static const String _endpointUrl = 'https://guardian-alert-backend.onrender.com/nearby-emergency-alert';

  static Future<void> sendNearbyAlert({
    required String alertId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('User must be signed in.');
    }

    if (_endpointUrl.isEmpty) {
      throw StateError(
        'Nearby alert backend URL has not been configured.',
      );
    }

    final idToken = await user.getIdToken();

    if (idToken == null || idToken.isEmpty) {
      throw StateError('Unable to obtain Firebase ID token.');
    }

    final response = await http
        .post(
          Uri.parse(_endpointUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'alertId': alertId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Nearby alert request failed '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }

  /// Registers a pending alert with Render so its independent 30-second
  /// timer can escalate it even if the phone later goes offline.
  static Future<void> registerPendingEmergency({
    required String alertId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in.');
    }

    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Unable to obtain Firebase ID token.');
    }

    final response = await http
        .post(
          Uri.parse('https://guardian-alert-backend.onrender.com/register-emergency-alert'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({'alertId': alertId}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(
        'Emergency timer registration failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}
