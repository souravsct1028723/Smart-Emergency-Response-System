import 'package:local_auth/local_auth.dart';

class BiometricService {
  static final LocalAuthentication _auth =
      LocalAuthentication();

  static Future<bool> isBiometricAvailable() async {
    try {
      final bool isSupported =
          await _auth.isDeviceSupported();

      final bool canCheck =
          await _auth.canCheckBiometrics;

      return isSupported && canCheck;
    } catch (e) {
      print(
        'BIOMETRIC SERVICE: Availability check failed: $e',
      );
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      final bool available =
          await isBiometricAvailable();

      if (!available) {
        print(
          'BIOMETRIC SERVICE: Biometrics unavailable.',
        );
        return false;
      }

      final bool authenticated =
          await _auth.authenticate(
        localizedReason:
            'Verify your identity to change your Guardian Alert password.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      print(
        'BIOMETRIC SERVICE: Authentication result = '
        '$authenticated',
      );

      return authenticated;
    } catch (e) {
      print(
        'BIOMETRIC SERVICE: Authentication failed: $e',
      );
      return false;
    }
  }
}