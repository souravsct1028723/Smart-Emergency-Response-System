import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/emergency_alert.dart';
import '../services/emergency_manager.dart';
import 'trusted_contacts_screen.dart';
import '../services/trusted_contact_service.dart';
import '../services/security_service.dart';
import '../services/notification_service.dart';
import '../services/sms_service.dart';
import '../services/firestore_emergency_service.dart';
import '../services/location_service.dart';
import '../services/nearby_alert_service.dart';
import 'settings_screen.dart';
import '../main.dart' show startGuardianService;

// --------------------
// Home Screen
// --------------------

class HomeScreen extends StatefulWidget {
  final bool startEmergencyOnOpen;

  const HomeScreen({
    super.key,
    this.startEmergencyOnOpen = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int countdown = 30;

  bool isEmergencyActive = false;
  bool emergencyTriggered = false;
  bool isLocationReady = false;

  Timer? emergencyTimer;

  double? latitude;
  double? longitude;

  EmergencyAlert? currentAlert;
  String? firestoreAlertId;

  @override
  void initState() {
    super.initState();

    EmergencyManager.setFallCallback(() {
      if (!mounted) return;

      if (!isEmergencyActive && !emergencyTriggered) {
        print(
          'HOME SCREEN: Fall confirmed. Starting emergency countdown.',
        );

        startEmergency();
      }
    });

    // Voice distress detection callback
    EmergencyManager.setVoiceEmergencyCallback(() {
      if (!mounted) return;

      if (!isEmergencyActive && !emergencyTriggered) {
        print('HOME SCREEN: Voice distress detected. Starting emergency countdown.');
        startEmergency();
      }
    });

    // Scream detection callback
    EmergencyManager.setScreamEmergencyCallback(() {
      if (!mounted) return;

      if (!isEmergencyActive && !emergencyTriggered) {
        print('HOME SCREEN: Scream detected. Starting emergency countdown.');
        startEmergency();
      }
    });

    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Start the existing background monitoring.
      await _initializeGuardianMonitoring();

      if (!mounted) return;

      // Process any emergency received before HomeScreen was ready.
      final pendingType = EmergencyManager.takePendingEmergency();

      if (widget.startEmergencyOnOpen || pendingType != null) {
        if (!isEmergencyActive && !emergencyTriggered) {
          debugPrint(
            'HOME SCREEN: Starting emergency countdown on launch. '
            'Pending event: $pendingType',
          );

          await startEmergency();
        }
      }
    });

  }

  
  Future<void> _initializeGuardianMonitoring() async {
    if (!mounted) return;

    final microphoneStatus = await Permission.microphone.status;

    if (!mounted) return;

    if (microphoneStatus.isGranted) {
      print('MICROPHONE: Permission already granted.');

      await startGuardianService(enableMicrophone: true);
    } else {
      print(
        'MICROPHONE: Permission not granted. '
        'Starting fall monitoring only.',
      );

      await startGuardianService();
    }
  }

  // --------------------------------------------------
  // PASSWORD-BASED EMERGENCY CANCELLATION
  // --------------------------------------------------

  Future<void> _requestEmergencyCancellation() async {
    if (!isEmergencyActive) {
      return;
    }

    final passwordController = TextEditingController();

    bool obscurePassword = true;
    String? errorMessage;

    final shouldCancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Cancel Emergency?',
              ),

              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your security password to cancel '
                    'the emergency alert.',
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Security Password',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            obscurePassword =
                                !obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),

                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),

              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      false,
                    );
                  },
                  child: const Text(
                    'Keep Alert Active',
                  ),
                ),

                ElevatedButton(
                  onPressed: () async {
                    final password =
                        passwordController.text;

                    if (password.isEmpty) {
                      setDialogState(() {
                        errorMessage =
                            'Please enter your password.';
                      });

                      return;
                    }

                    final isCorrect =
                        await SecurityService.verifyPassword(
                      password,
                    );

                    if (isCorrect) {
                      if (dialogContext.mounted) {
                        Navigator.pop(
                          dialogContext,
                          true,
                        );
                      }
                    } else {
                      setDialogState(() {
                        errorMessage =
                            'Incorrect password.';
                      });

                      passwordController.clear();
                    }
                  },
                  child: const Text(
                    'Verify & Cancel',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      passwordController.dispose();
    });

    if (shouldCancel == true) {
      await cancelEmergency();
    }
  }

  // --------------------------------------------------
  // EMERGENCY SMS
  // --------------------------------------------------

  Future<void> _sendEmergencySms() async {
    final contacts =
        await TrustedContactService.loadContacts();

    if (contacts.isEmpty) {
      print(
        'HOME SCREEN: No Emergency Circle contacts found.',
      );

      return;
    }

    final double? lat = currentAlert?.latitude;
    final double? lon = currentAlert?.longitude;

    String locationText;

    if (lat != null && lon != null) {
      locationText =
          'https://maps.google.com/?q=$lat,$lon';
    } else {
      locationText = 'Location unavailable';
    }

    final String message =
        'GUARDIAN ALERT\n\n'
        'Fall detected.\n\n'
        'Please check the person immediately.\n\n'
        'Location:\n'
        '$locationText';

    int successCount = 0;

    for (final contact in contacts) {
      print(
        'HOME SCREEN: Sending emergency SMS to '
        '${contact.name} (${contact.phoneNumber})',
      );

      final bool success =
          await SmsService.sendEmergencySms(
        phoneNumber: contact.phoneNumber,
        message: message,
      );

      if (success) {
        successCount++;

        print(
          'HOME SCREEN: Emergency SMS submitted successfully '
          'to ${contact.name}.',
        );
      } else {
        print(
          'HOME SCREEN: Emergency SMS failed '
          'for ${contact.name}.',
        );
      }
    }

    print(
      'HOME SCREEN: Emergency SMS completed. '
      '$successCount/${contacts.length} messages submitted.',
    );
  }

  // --------------------------------------------------
  // LOCATION
  // --------------------------------------------------

  
Future<void> fetchEmergencyLocation() async {
  if (!mounted || !isEmergencyActive) return;

  setState(() {
    isLocationReady = false;
  });

  try {
    final position = await LocationService.getCurrentLocation();

    if (!mounted || !isEmergencyActive) return;

    if (position == null) {
      print('HOME SCREEN: Unable to acquire emergency location.');
      return;
    }

    setState(() {
      latitude = position.latitude;
      longitude = position.longitude;
      isLocationReady = true;

      if (currentAlert != null) {
        currentAlert = EmergencyAlert(
          alertType: currentAlert!.alertType,
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: currentAlert!.timestamp,
          status: currentAlert!.status,
        );
      }
    });

    print('Location: $latitude, $longitude');

    // Start the countdown immediately after obtaining the location.
    _startEmergencyCountdown();

    // Update Firebase separately; do not block the countdown.
    final alertId = firestoreAlertId;

    if (alertId == null) {
      print(
        'HOME SCREEN: Location acquired; waiting for Firebase alert ID.',
      );
      return;
    }

    try {
      await FirestoreEmergencyService.updateEmergencyAlertLocation(
        alertId: alertId,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      print(
        'HOME SCREEN: Failed to update alert location in Firebase: $e',
      );
    }
  } catch (e) {
    print('HOME SCREEN: Location acquisition failed: $e');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not acquire the emergency location.'),
      ),
    );
  }
}


  // --------------------------------------------------
  // START EMERGENCY
  // --------------------------------------------------  

Future<void> startEmergency() async {
  if (isEmergencyActive || emergencyTriggered) return;

  emergencyTimer?.cancel();
  firestoreAlertId = null;

  setState(() {
    isEmergencyActive = true;
    countdown = 30;
    isLocationReady = false;
    latitude = null;
    longitude = null;
  });

  currentAlert = EmergencyAlert(
    alertType: 'SOS',
    latitude: null,
    longitude: null,
    timestamp: DateTime.now(),
    status: 'pending',
  );

  // Start location acquisition immediately.
  // Do not wait for Firebase before requesting the location.
  final locationFuture = fetchEmergencyLocation();

  // Save the alert independently.
  // A Firebase failure must not stop location acquisition.
  _savePendingEmergency();

  await locationFuture;
}


  
Future<bool> _savePendingEmergency() async {
  try {
    final userName =
        await FirestoreEmergencyService.getCurrentUserName();

    if (!mounted || !isEmergencyActive) return false;

    final alert = currentAlert;
    if (alert == null) return false;

    final alertId =
        await FirestoreEmergencyService.saveEmergencyAlert(
      alert,
      userName: userName,
    );

    if (!mounted) return false;

    
    firestoreAlertId = alertId;
    print('HOME SCREEN: Pending alert saved with ID: $alertId');

    // Register the independent server-side 30-second timer immediately.
    // If this fails, keep the local countdown and log the failure.
    try {
      await NearbyAlertService.registerPendingEmergency(
        alertId: alertId,
      );
      print('HOME SCREEN: Server-side emergency timer registered.');
    } catch (error) {
      print('HOME SCREEN: Server timer registration failed: $error');
    }

    // If location was acquired before Firebase finished saving,
    // upload the coordinates now.
    if (isLocationReady && latitude != null && longitude != null) {
      try {
        await FirestoreEmergencyService.updateEmergencyAlertLocation(
        alertId: alertId,
        latitude: latitude!,
        longitude: longitude!,
        );
      } catch (e) {
        print('HOME SCREEN: Failed to sync location to Firebase: $e',);
      }
    }

    return true;

  } catch (e) {
    print('HOME SCREEN: Failed to save pending alert: $e');

    if (!mounted) return false;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not save emergency to the server. Please check your connection.',
        ),
      ),
    );
    return false;
  }
}


void _startEmergencyCountdown() {
  emergencyTimer?.cancel();

  emergencyTimer = Timer.periodic(
    const Duration(seconds: 1),
    (timer) {
      if (!mounted || !isEmergencyActive) {
        timer.cancel();
        return;
      }

      if (countdown > 1) {
        setState(() {
          countdown--;
        });
      } else {
        timer.cancel();
        _triggerEmergency();
      }
    },
  );
}


void _triggerEmergency() {
  if (!mounted || !isEmergencyActive || emergencyTriggered) {
    return;
  }

  emergencyTimer?.cancel();
  emergencyTimer = null;

  // Keep the Firebase document ID before changing state.
  final alertId = firestoreAlertId;

  setState(() {
    countdown = 0;
    isEmergencyActive = false;
    emergencyTriggered = true;

    if (currentAlert != null) {
      currentAlert = EmergencyAlert(
        alertType: currentAlert!.alertType,
        latitude: currentAlert!.latitude,
        longitude: currentAlert!.longitude,
        timestamp: currentAlert!.timestamp,
        status: 'triggered',
      );
    }
  });

  print('EMERGENCY ALERT TRIGGERED');

  if (alertId != null) {
    FirestoreEmergencyService.updateEmergencyAlertStatus(
      alertId: alertId,
      status: 'triggered',
    ).then((_) async {
      print('HOME SCREEN: Firebase status updated to triggered.');

      try {
        await NearbyAlertService.sendNearbyAlert(
          alertId: alertId,
        );

        print('HOME SCREEN: Nearby alert request completed.');
      } catch (e) {
        print('HOME SCREEN: Nearby alert request failed: $e');
      }
    }).catchError((Object e) {
      print('HOME SCREEN: Failed to update triggered status: $e');
    });
  } else {
    print('HOME SCREEN: No Firestore alert ID available.');
  }

  // Preserve the existing emergency SMS behavior.
  _sendEmergencySms();
}


void _sendNow() {
  if (!isEmergencyActive || !isLocationReady) {
    return;
  }

  print('HOME SCREEN: User selected Send now.');

  // Stop the countdown before triggering the emergency.
  emergencyTimer?.cancel();
  emergencyTimer = null;

  _triggerEmergency();
}



  // --------------------------------------------------
  // CANCEL EMERGENCY
  // --------------------------------------------------

  
Future<void> cancelEmergency() async {
  emergencyTimer?.cancel();
  emergencyTimer = null;

  // Keep the alert ID before clearing the current alert.
  final alertId = firestoreAlertId;

  try {
    await NotificationService.cancelEmergencyNotification();

    // Update Firebase if a pending alert was saved.
    if (alertId != null) {
      await FirestoreEmergencyService.updateEmergencyAlertStatus(
        alertId: alertId,
        status: 'cancelled',
      );
    }
  } catch (e) {
    print('HOME SCREEN: Failed to update cancellation status: $e');
  }

  if (!mounted) return;

  setState(() {
    isEmergencyActive = false;
    emergencyTriggered = false; // Allow future emergency detections
    countdown = 30;
    isLocationReady = false;
    latitude = null;
    longitude = null;
    currentAlert = null;
    firestoreAlertId = null;
  });

  FlutterForegroundTask.sendDataToTask({
    'type': 'reset_emergency_triggers',
  });

  print('HOME SCREEN: Emergency cancelled.');
}

  // --------------------------------------------------
  // DISPOSE
  // --------------------------------------------------

  @override
  void dispose() {
    EmergencyManager.clearCallback();
    EmergencyManager.clearVoiceEmergencyCallback();
    EmergencyManager.clearScreamEmergencyCallback();

    emergencyTimer?.cancel();

    super.dispose();
  }

  // --------------------------------------------------
  // BUILD
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],

      appBar: AppBar(
        title: const Text(
          'Guardian Alert',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),

      body: emergencyTriggered
          ? _emergencyTriggeredScreen()
          : SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),

                  child: Column(
                    children: [
                      // --------------------
                      // Welcome message
                      // --------------------

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Stay Safe',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(height: 5),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Your emergency protection is active.',
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                      const SizedBox(height: 35),

                      // --------------------
                      // SOS Button
                      // --------------------

                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isEmergencyActive
                              ? Colors.orange
                              : Colors.red,
                        ),

                        child: Material(
                          color: Colors.transparent,

                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(110),

                            onTap: isEmergencyActive
                                ? null
                                : () {
                                    startEmergency();
                                  },

                            child: Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,

                                children: [
                                  Icon(
                                    isEmergencyActive
                                        ? Icons.timer
                                        : Icons.warning_rounded,
                                    color: Colors.white,
                                    size: 55,
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    isEmergencyActive
                                        ? '$countdown'
                                        : 'SOS',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),

                                  Text(
                                    isEmergencyActive
                                        ? 'EMERGENCY ACTIVE'
                                        : 'TAP FOR HELP',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // --------------------
                      // Emergency cancellation
                      // --------------------

                      if (isEmergencyActive) ...[
                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 50,

                          child: ElevatedButton(
                            onPressed:
                                _requestEmergencyCancellation,

                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.red,

                              side: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),

                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),

                            child: const Text(
                              'CANCEL ALERT',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        
                        if (isLocationReady)
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _sendNow,
                              icon: const Icon(Icons.send),
                              label: const Text(
                                'SEND NOW',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                            ),
                          ),
                        
                        const SizedBox(height: 10),

                        Text(
                          isLocationReady
                              ? '📍 Location ready'
                              : '📍 Acquiring location...',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],

                      const SizedBox(height: 35),

                      // --------------------
                      // Status cards
                      // --------------------

                      Row(
                        children: [
                          Expanded(
                            child: _statusCard(
                              Icons.location_on,
                              'Location',
                              'Available',
                            ),
                          ),

                          const SizedBox(width: 15),

                          Expanded(
                            child: _statusCard(
                              Icons.watch,
                              'Wearable',
                              'Not Connected',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // --------------------
                      // Emergency Circle
                      // --------------------

                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const TrustedContactsScreen(),
                            ),
                          );
                        },

                        icon: const Icon(
                          Icons.people_outline,
                          size: 18,
                        ),

                        label: const Text(
                          'Emergency Circle',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // --------------------------------------------------
  // EMERGENCY TRIGGERED SCREEN
  // --------------------------------------------------

  Widget _emergencyTriggeredScreen() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),

          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [
              const Icon(
                Icons.warning_rounded,
                color: Colors.red,
                size: 90,
              ),

              const SizedBox(height: 25),

              const Text(
                'EMERGENCY ALERT',
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Your emergency alert has been triggered.',
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 20),

              if (currentAlert != null) ...[
                Text(
                  'Status: ${currentAlert!.status}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Alert Type: Fall Detected',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  currentAlert!.latitude != null &&
                          currentAlert!.longitude != null
                      ? 'Location: '
                          '${currentAlert!.latitude}, '
                          '${currentAlert!.longitude}'
                      : 'Location: Not available',
                  textAlign: TextAlign.center,

                  style: const TextStyle(
                    fontSize: 15,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Time: ${currentAlert!.timestamp}',
                  textAlign: TextAlign.center,

                  style: const TextStyle(
                    fontSize: 15,
                  ),
                ),
              ],

              const SizedBox(height: 35),

              SizedBox(
                width: double.infinity,
                height: 55,

                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      emergencyTriggered = false;
                      countdown = 60;
                    });
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                    ),
                  ),

                  child: const Text(
                    'RETURN TO HOME',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // STATUS CARD
  // --------------------------------------------------

  Widget _statusCard(
    IconData icon,
    String title,
    String status,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),

      child: Column(
        children: [
          Icon(
            icon,
            size: 30,
            color: Colors.red,
          ),

          const SizedBox(height: 8),

          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            status,
            textAlign: TextAlign.center,

            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}