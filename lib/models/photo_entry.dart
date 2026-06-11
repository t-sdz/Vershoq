import 'dart:convert';

class PhotoEntry {
  final String id;
  final String personName;
  final String localPath;
  final String? remoteUrl;
  final DateTime timestamp;

  const PhotoEntry({
    required this.id,
    required this.personName,
    required this.localPath,
    this.remoteUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'personName': personName,
        'localPath': localPath,
        'remoteUrl': remoteUrl,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PhotoEntry.fromJson(Map<String, dynamic> json) => PhotoEntry(
        id: json['id'] as String,
        personName: json['personName'] as String,
        localPath: json['localPath'] as String,
        remoteUrl: json['remoteUrl'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  static List<PhotoEntry> listFromJsonString(String s) =>
      (jsonDecode(s) as List)
          .map((e) => PhotoEntry.fromJson(e as Map<String, dynamic>))
          .toList();
}
