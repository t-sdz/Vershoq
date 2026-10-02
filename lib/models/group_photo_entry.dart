import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

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

  /// Cache des images décodées (par id de photo) : le base64 n'est décodé
  /// qu'une fois, même si l'écran se reconstruit. Limité aux plus récentes.
  static final LinkedHashMap<String, Uint8List> _bytesCache =
      LinkedHashMap<String, Uint8List>();
  static const _maxCached = 60;

  /// Image décodée (null si invalide).
  Uint8List? get bytes {
    final hit = _bytesCache.remove(id);
    if (hit != null) {
      _bytesCache[id] = hit; // devient la plus récente
      return hit;
    }
    try {
      final b = base64Decode(imageBase64);
      if (b.isEmpty) return null;
      _bytesCache[id] = b;
      while (_bytesCache.length > _maxCached) {
        _bytesCache.remove(_bytesCache.keys.first);
      }
      return b;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toMap() => {
        'personName': personName,
        'uploaderUsername': uploaderUsername,
        'uploaderEmail': uploaderEmail,
        'imageBase64': imageBase64,
        'timestamp': timestamp.toIso8601String(),
        if (challenge != null) 'challenge': challenge,
      };
}
