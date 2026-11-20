
class NearbyUser {
  final String uid;
  final double latitude;
  final double longitude;
  final DateTime? updatedAt;

  const NearbyUser({
    required this.uid,
    required this.latitude,
    required this.longitude,
    this.updatedAt,
  });
}

