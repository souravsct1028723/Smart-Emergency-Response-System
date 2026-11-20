
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class EmergencyDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> alertData;

  const EmergencyDetailsScreen({
    super.key,
    required this.alertData,
  });

  @override
  State<EmergencyDetailsScreen> createState() =>
      _EmergencyDetailsScreenState();
}

class _EmergencyDetailsScreenState
    extends State<EmergencyDetailsScreen> {
  static const String _backendUrl =
      'https://guardian-alert-backend.onrender.com';

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _details;

  @override
  void initState() {
    super.initState();
    _loadEmergencyDetails();
  }

  Future<void> _loadEmergencyDetails() async {
    final alertId = widget.alertData['alertId']?.toString();

    if (alertId == null || alertId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Emergency ID is missing.';
        _isLoading = false;
      });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Please sign in to view this emergency.');
      }

      final idToken = await user.getIdToken(true);

      if (idToken == null || idToken.isEmpty) {
        throw Exception('Could not authenticate your account.');
      }

      final uri = Uri.parse(
        '$_backendUrl/nearby-emergency-details',
      ).replace(
        queryParameters: {'alertId': alertId},
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response from the server.');
      }

      if (response.statusCode != 200) {
        final message = decoded['error']?.toString();

        throw Exception(
          message ?? 'Unable to retrieve emergency details.',
        );
      }

      final alert = decoded['alert'];

      if (alert is! Map<String, dynamic>) {
        throw Exception('Emergency details are unavailable.');
      }

      if (!mounted) return;

      setState(() {
        _details = alert;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _details ?? widget.alertData;

    final userName =
        data['userName']?.toString() ?? 'Unknown user';
    final latitude =
        data['latitude']?.toString() ?? 'Unavailable';
    final longitude =
        data['longitude']?.toString() ?? 'Unavailable';
    final status =
        data['status']?.toString() ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Details'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null && _details == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 48,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _error = null;
                            });
                            _loadEmergencyDetails();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 64,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Nearby Emergency Alert',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _detailTile('Reported by', userName),
                    _detailTile('Status', status),
                    _detailTile('Latitude', latitude),
                    _detailTile('Longitude', longitude),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                        onPressed: _details == null
                            ? null
                            : _openEmergencyLocation,
                        icon: const Icon(Icons.location_on),
                        label: const Text('View Emergency Location on Google Maps'),
                    ),
                    _detailTile(
                      'Emergency ID',
                      widget.alertData['alertId']?.toString()
                          ?? 'Unavailable',
                    ),
                    const SizedBox(height: 20),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.orange,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  ],
                ),
    );
  }

  Future<void> _openEmergencyLocation() async {
    final data = _details ?? widget.alertData;

    final latitude = double.tryParse(
        data['latitude']?.toString() ?? '',
    );

    final longitude = double.tryParse(
        data['longitude']?.toString() ?? '',
    );

    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Emergency location is unavailable.'),
            ),
        );
        return;
    }

    final uri = Uri.https(
        'www.google.com',
        '/maps/search/',
        {
            'api': '1',
            'query': '$latitude,$longitude',
        },
    );

    try {
        final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
        );

        if (!opened) {
            throw Exception('Could not open Maps');
        }
    } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Unable to open Google Maps.'),
            ),
        );
    }
  }

  Widget _detailTile(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
