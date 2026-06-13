class GroupPhotoEntry {
  final String id;
  final String personName;
  final String uploaderUsername;
  final String uploaderEmail;
  final String imageBase64;
  final DateTime timestamp;

  const GroupPhotoEntry({
    required this.id,
    required this.personName,
    required this.uploaderUsername,
    required this.uploaderEmail,
    required this.imageBase64,
    required this.timestamp,
  });

  factory GroupPhotoEntry.fromMap(String id, Map<String, dynamic> map) =>
      GroupPhotoEntry(
        id: id,
        personName: map['personName'] as String? ?? '',
        uploaderUsername: map['uploaderUsername'] as String? ?? '',
        uploaderEmail: map['uploaderEmail'] as String? ?? '',
        imageBase64: map['imageBase64'] as String? ?? '',
        timestamp:
            DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'personName': personName,
        'uploaderUsername': uploaderUsername,
        'uploaderEmail': uploaderEmail,
        'imageBase64': imageBase64,
        'timestamp': timestamp.toIso8601String(),
      };
}
