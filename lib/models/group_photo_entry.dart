class GroupPhotoEntry {
  final String id;
  final String personName;
  final String uploaderUsername;
  final String uploaderEmail;
  final String imageBase64;
  final DateTime timestamp;

  /// Texte du défi (mode Défis), null pour une photo spontanée classique.
  final String? challenge;

  const GroupPhotoEntry({
    required this.id,
    required this.personName,
    required this.uploaderUsername,
    required this.uploaderEmail,
    required this.imageBase64,
    required this.timestamp,
    this.challenge,
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
        challenge: (map['challenge'] as String?)?.isNotEmpty == true
            ? map['challenge'] as String
            : null,
      );

  Map<String, dynamic> toMap() => {
        'personName': personName,
        'uploaderUsername': uploaderUsername,
        'uploaderEmail': uploaderEmail,
        'imageBase64': imageBase64,
        'timestamp': timestamp.toIso8601String(),
        if (challenge != null) 'challenge': challenge,
      };
}
