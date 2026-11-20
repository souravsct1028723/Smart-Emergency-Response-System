
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:autostart_settings/autostart_settings.dart';

class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  bool _loading = false;

  bool _notificationsGranted = false;
  bool _locationGranted = false;
  bool _backgroundLocationGranted = false;
  bool _microphoneGranted = false;

  String? _message;

  Future<void> _requestPermissions() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      // 1. Request notification permission.
      final notificationSettings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      _notificationsGranted =
          notificationSettings.authorizationStatus ==
                  AuthorizationStatus.authorized ||
              notificationSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      // 2. Request microphone permission for voice
      // distress and scream detection.
      final microphoneStatus =
          await Permission.microphone.request();

      _microphoneGranted = microphoneStatus.isGranted;

      // 3. Check whether location services are enabled.
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _message =
                'Please turn on Location/GPS in your phone settings, '
                'then tap Allow Permissions again.';
          });
        }
        return;
      }

      // 4. Request foreground location permission.
      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _message =
                'Location permission is permanently denied. '
                'Open App Settings and allow location access.';
          });
        }
        return;
      }

      _locationGranted =
          permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always;

      _backgroundLocationGranted =
          permission == LocationPermission.always;

      // 5. Display the current permission status.
      if (mounted) {
        setState(() {
          if (!_microphoneGranted) {
            _message =
                'Microphone permission is required for voice and '
                'scream detection. Please allow microphone access.';
          } else if (!_locationGranted) {
            _message =
                'Location permission is required for emergency '
                'location sharing. Please allow it and try again.';
          } else if (!_backgroundLocationGranted) {
            _message =
                'Background location is not enabled. Open App Settings '
                'and select Allow all the time if this option is available.';
          } else if (!_notificationsGranted) {
            _message =
                'Notifications are not allowed. You can enable them '
                'in App Settings.';
          } else {
            _message =
                'Required notification, location, and microphone '
                'permissions have been granted.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Could not request permissions: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  void _continueToHome() {
    if (!_locationGranted ||
        !_notificationsGranted ||
        !_backgroundLocationGranted ||
        !_microphoneGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enable notification, location, background '
            'location, and microphone permissions before continuing.',
          ),
        ),
      );
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Setup'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 72,
                color: Colors.red,
              ),
              const SizedBox(height: 20),
              const Text(
                'Set up Guardian Alert',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Allow these permissions so Guardian Alert can '
                'monitor emergencies, notify you about nearby '
                'emergencies, and share your location when needed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              _permissionRow(
                'Notifications',
                _notificationsGranted,
              ),
              _permissionRow(
                'Microphone (voice and scream detection)',
                _microphoneGranted,
              ),
              _permissionRow(
                'Location while using the app',
                _locationGranted,
              ),
              _permissionRow(
                'Background location',
                _backgroundLocationGranted,
              ),

              const SizedBox(height: 20),

              if (_message != null)
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _loading ? null : _requestPermissions,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: Text(
                  _loading ? 'Requesting...' : 'Allow Permissions',
                ),
              ),

              const SizedBox(height: 10),

              OutlinedButton(
                onPressed: _openSettings,
                child: const Text(
                  'Open App Settings',
                ),
              ),

              OutlinedButton(
                onPressed: _configureBatteryOptimization,
                child: const Text(
                  'Configure Background Battery Settings',
                ),
              ),

              OutlinedButton.icon(
                onPressed: _loading ? null : _openAutoStartSettings,
                icon: const Icon(Icons.rocket_launch),
                label: const Text(
                    'Enable Auto-Start & Background Activity',
                ),
              ),

              const SizedBox(height: 10),

              TextButton(
                onPressed: _continueToHome,
                child: const Text('Continue to Guardian Alert'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionRow(String title, bool granted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Icon(
            granted
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: granted ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          Text(
            granted ? 'Granted' : 'Pending',
            style: TextStyle(
              color: granted ? Colors.green : Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configureBatteryOptimization() async {
    final isExempt =
        await FlutterForegroundTask.isIgnoringBatteryOptimizations;

    if (isExempt) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Battery optimization is already disabled for Guardian Alert.',
          ),
        ),
      );
      return;
    }

    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  Future<void> _openAutoStartSettings() async {
    try {
        final canOpen = await AutostartSettings.canOpen(
            autoStart: true,
            batterySafer: true,
        );

        if (!mounted) return;

        if (canOpen) {
            await AutostartSettings.open(
                autoStart: true,
                batterySafer: true,
            );
        } else {
            await Geolocator.openAppSettings();
        }
    } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not open background settings. '
                    'Please open Guardian Alert settings manually.',
                ),
            ),
        );

        await Geolocator.openAppSettings();
    }
  }

}
