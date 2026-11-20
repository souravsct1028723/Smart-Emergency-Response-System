
class EmergencyManager {
  static void Function()? _onFallConfirmed;
  static void Function()? _onVoiceEmergencyDetected;
  static void Function()? _onScreamEmergencyDetected;

  static String? _pendingEmergencyType;

  static void setFallCallback(void Function() callback) {
    _onFallConfirmed = callback;
  }

  static void notifyFallConfirmed() {
    final callback = _onFallConfirmed;
    if (callback != null) {
      callback();
    } else {
      _pendingEmergencyType ??= 'fall';
    }
  }

  static void clearCallback() {
    _onFallConfirmed = null;
  }

  static void setVoiceEmergencyCallback(void Function() callback) {
    _onVoiceEmergencyDetected = callback;
  }

  static void notifyVoiceEmergencyDetected() {
    final callback = _onVoiceEmergencyDetected;
    if (callback != null) {
      callback();
    } else {
      _pendingEmergencyType ??= 'voice';
    }
  }

  static void clearVoiceEmergencyCallback() {
    _onVoiceEmergencyDetected = null;
  }

  static void setScreamEmergencyCallback(void Function() callback) {
    _onScreamEmergencyDetected = callback;
  }

  static void notifyScreamEmergencyDetected() {
    final callback = _onScreamEmergencyDetected;
    if (callback != null) {
      callback();
    } else {
      _pendingEmergencyType ??= 'scream';
    }
  }

  static void clearScreamEmergencyCallback() {
    _onScreamEmergencyDetected = null;
  }

  static String? takePendingEmergency() {
    final type = _pendingEmergencyType;
    _pendingEmergencyType = null;
    return type;
  }
}
