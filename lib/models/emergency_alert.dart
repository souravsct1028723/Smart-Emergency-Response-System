class EmergencyAlert {
  final String alertType;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final String status;

  EmergencyAlert({
    required this.alertType,
    this.latitude,
    this.longitude,
    required this.timestamp,
    required this.status,
  });
}