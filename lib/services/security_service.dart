
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecurityService {
  static const FlutterSecureStorage _storage =
      FlutterSecureStorage();

  // Use a separate secure-storage key for each Firebase user.
  static String get _passwordKey {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError(
        'A Firebase user must be signed in to access the security password.',
      );
    }

    return 'guardian_alert_password_${user.uid}';
  }

  /// Checks whether the signed-in user has created
  /// an emergency-cancellation password.
  static Future<bool> hasPassword() async {
    final password = await _storage.read(
      key: _passwordKey,
    );

    return password != null && password.isNotEmpty;
  }

  /// Saves the signed-in user's emergency-cancellation password.
  static Future<void> setPassword(String password) async {
    await _storage.write(
      key: _passwordKey,
      value: password,
    );

    print('SECURITY SERVICE: Password saved for current user.');
  }

  /// Verifies the signed-in user's emergency-cancellation password.
  static Future<bool> verifyPassword(String password) async {
    final savedPassword = await _storage.read(
      key: _passwordKey,
    );

    if (savedPassword == null) {
      return false;
    }

    return savedPassword == password;
  }

  /// Deletes only the signed-in user's stored password.
  static Future<void> clearPassword() async {
    await _storage.delete(
      key: _passwordKey,
    );

    print('SECURITY SERVICE: Password cleared for current user.');
  }
}
