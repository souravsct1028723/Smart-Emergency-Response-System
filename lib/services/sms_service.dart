import 'package:flutter/services.dart';

class SmsService {
  static const MethodChannel _channel =
      MethodChannel('guardian_alert/sms');

  static Future<bool> sendEmergencySms({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final bool result = await _channel.invokeMethod(
        'sendSms',
        {
          'phoneNumber': phoneNumber,
          'message': message,
        },
      );

      print('SMS SERVICE: Send result = $result');

      return result;
    } catch (e) {
      print('SMS SERVICE ERROR: $e');
      return false;
    }
  }
}