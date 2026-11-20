import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/background_location_service.dart';
import '../services/location_permission_service.dart';
import '../services/nearby_location_firestore_service.dart';

import 'security_settings_screen.dart';
import 'welcome_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Nearby-alert location preference.
  bool _shareLocation = false;
  bool _isLoadingPreference = true;

  // Smart Mute preference.
  static const String _smartMuteKey = 'smartMuteUntilEpochMs';

  int? _smartMuteUntilMs;
  bool _isLoadingSmartMute = true;

  bool get _isSmartMuteActive =>
      _smartMuteUntilMs != null &&
      _smartMuteUntilMs! > DateTime.now().millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _loadLocationPreference();
    _loadSmartMutePreference();
  }

  // --------------------------------------------------
  // LOCATION SHARING
  // --------------------------------------------------

  Future<void> _loadLocationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getBool('shareLocationForNearbyAlerts') ?? false;

    if (!mounted) return;

    setState(() {
      _shareLocation = savedValue;
      _isLoadingPreference = false;
    });
  }

  Future<void> _saveLocationPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (!value) {
      await prefs.setBool('shareLocationForNearbyAlerts', false);

      if (mounted) {
        setState(() {
          _shareLocation = false;
        });
      }

      try {
        await NearbyLocationFirestoreService.saveNearbyAlertConsent(
          enabled: false,
        );
        debugPrint('NEARBY ALERTS: Consent disabled in Firestore.');
      } catch (e) {
        debugPrint('NEARBY ALERTS: Failed to disable consent: $e');
      }

      try {
        await BackgroundLocationService.cancelLocationUpdates();
        debugPrint('BACKGROUND LOCATION: Updates cancelled.');
      } catch (e) {
        debugPrint('BACKGROUND LOCATION: Cancellation failed: $e');
      }

      return;
    }

    final permissionGranted =
        await LocationPermissionService.requestLocationPermissions();

    if (!mounted) return;

    if (!permissionGranted) {
      await prefs.setBool('shareLocationForNearbyAlerts', false);

      if (!mounted) return;

      setState(() {
        _shareLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Background location permission is required.'),
        ),
      );

      return;
    }

    try {
      await BackgroundLocationService.scheduleLocationUpdates();

      await NearbyLocationFirestoreService.saveNearbyAlertConsent(
        enabled: true,
      );

      debugPrint('NEARBY ALERTS: Consent enabled in Firestore.');

      await prefs.setBool('shareLocationForNearbyAlerts', true);

      if (!mounted) return;

      setState(() {
        _shareLocation = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nearby-alert location updates scheduled.'),
        ),
      );

      debugPrint('BACKGROUND LOCATION: Updates scheduled.');
    } catch (e) {
      await prefs.setBool('shareLocationForNearbyAlerts', false);

      try {
        await BackgroundLocationService.cancelLocationUpdates();
        debugPrint('BACKGROUND LOCATION: Updates cancelled after failure.');
      } catch (cancelError) {
        debugPrint('BACKGROUND LOCATION: Cancellation failed: $cancelError');
      }

      try {
        await NearbyLocationFirestoreService.saveNearbyAlertConsent(
          enabled: false,
        );
      } catch (consentError) {
        debugPrint(
          'NEARBY ALERTS: Failed to disable consent after failure: '
          '$consentError',
        );
      }

      if (!mounted) return;

      setState(() {
        _shareLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not enable nearby alerts. Please try again.'),
        ),
      );

      debugPrint('NEARBY ALERTS: Enabling failed: $e');
    }
  }

  // --------------------------------------------------
  // SMART MUTE
  // --------------------------------------------------

  Future<void> _loadSmartMutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUntil = prefs.getInt(_smartMuteKey);
    final now = DateTime.now().millisecondsSinceEpoch;

    final activeUntil = savedUntil != null && savedUntil > now
        ? savedUntil
        : null;

    if (savedUntil != null && activeUntil == null) {
      await prefs.remove(_smartMuteKey);
    }

    if (!mounted) return;

    setState(() {
      _smartMuteUntilMs = activeUntil;
      _isLoadingSmartMute = false;
    });

    // Restore the saved mute state in the foreground task.
    _sendSmartMuteToTask(activeUntil);
  }

  void _sendSmartMuteToTask(int? untilMs) {
    try {
      FlutterForegroundTask.sendDataToTask({
        'type': 'smart_mute_until',
        'until': untilMs ?? 0,
      });
    } catch (e) {
      debugPrint('SMART MUTE: Could not notify foreground task: $e');
    }
  }

  Future<void> _enableSmartMute(int hours) async {
    final until = DateTime.now()
        .add(Duration(hours: hours))
        .millisecondsSinceEpoch;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_smartMuteKey, until);

    if (!mounted) return;

    setState(() {
      _smartMuteUntilMs = until;
    });

    _sendSmartMuteToTask(until);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Voice distress and scream detection muted for $hours '
          '${hours == 1 ? 'hour' : 'hours'}. Fall detection remains active.',
        ),
      ),
    );
  }

  Future<void> _disableSmartMute() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_smartMuteKey);

    if (!mounted) return;

    setState(() {
      _smartMuteUntilMs = null;
    });

    _sendSmartMuteToTask(null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Smart Mute disabled. Voice and scream detection can resume.',
        ),
      ),
    );
  }

  Future<void> _showSmartMuteOptions() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Smart Mute',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Temporarily disable voice-distress and scream '
                'detection. Fall detection and other emergency '
                'features remain active.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              for (final hours in [1, 3, 6, 12])
                ListTile(
                  leading: const Icon(Icons.volume_off_outlined),
                  title: Text('$hours ${hours == 1 ? 'hour' : 'hours'}'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _enableSmartMute(hours);
                  },
                ),
              if (_isSmartMuteActive)
                ListTile(
                  leading: const Icon(
                    Icons.volume_up_outlined,
                    color: Colors.green,
                  ),
                  title: const Text('Turn Smart Mute off now'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _disableSmartMute();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatMuteExpiry() {
    final until = _smartMuteUntilMs;
    if (until == null) return '';

    final expiry = DateTime.fromMillisecondsSinceEpoch(until).toLocal();

    final date =
        '${expiry.day.toString().padLeft(2, '0')}/'
        '${expiry.month.toString().padLeft(2, '0')}/'
        '${expiry.year}';

    final time =
        '${expiry.hour.toString().padLeft(2, '0')}:'
        '${expiry.minute.toString().padLeft(2, '0')}';

    return 'Active until $date, $time';
  }

  // --------------------------------------------------
  // SETTINGS UI
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Security',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: const Icon(Icons.security, color: Colors.red),
              title: const Text(
                'Security Settings',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Manage your emergency cancellation password.',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SecuritySettingsScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Nearby Emergency Alerts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: SwitchListTile(
              secondary: _isLoadingPreference
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.location_on_outlined, color: Colors.red),
              title: const Text(
                'Share location for nearby alerts',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _isLoadingPreference
                    ? 'Loading preference...'
                    : _shareLocation
                    ? 'Enabled. Background location updates are scheduled.'
                    : 'Disabled. Your location will not be collected '
                          'for nearby alerts.',
              ),
              value: _shareLocation,
              onChanged: _isLoadingPreference ? null : _saveLocationPreference,
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Emergency Features',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: ListTile(
              leading: Icon(
                _isSmartMuteActive
                    ? Icons.volume_off
                    : Icons.volume_up_outlined,
                color: _isSmartMuteActive ? Colors.orange : Colors.grey,
              ),
              title: const Text(
                'Smart Mute',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _isLoadingSmartMute
                    ? 'Loading preference...'
                    : _isSmartMuteActive
                    ? '${_formatMuteExpiry()}\n'
                          'Voice and scream detection are muted.'
                    : 'Temporarily mute voice and scream detection.',
              ),
              isThreeLine: _isSmartMuteActive,
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: _isLoadingSmartMute ? null : _showSmartMuteOptions,
            ),
          ),

          const SizedBox(height: 24),

          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
              subtitle: const Text('Sign out of your Guardian Alert account.'),
              onTap: () async {
                final shouldLogout = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Logout?'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, false);
                        },
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, true);
                        },
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );

                if (shouldLogout != true || !context.mounted) {
                  return;
                }

                await FirebaseAuth.instance.signOut();

                if (!context.mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
