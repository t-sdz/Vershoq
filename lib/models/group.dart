class Group {
  final String id;
  final String name;
  final String code;
  final String createdByEmail;
  final String createdByUsername;
  final DateTime createdAt;

  /// Emails des administrateurs. Le créateur en fait toujours partie.
  final List<String> admins;

  /// Photo du groupe (base64), modifiable par un admin.
  final String? photoBase64;

  /// Config des notifications, partagée par tous les membres (fixée par
  /// l'admin) : horaires, nombre de notifs/jour, nombre de noms par photo…
  final Map<String, dynamic>? notifConfig;

  const Group({
    required this.id,
    required this.name,
    required this.code,
    required this.createdByEmail,
    required this.createdByUsername,
    required this.createdAt,
    this.admins = const [],
    this.photoBase64,
    this.notifConfig,
  });

  /// Un email est admin s'il est dans la liste OU s'il est le créateur.
  bool isAdmin(String? email) {
    if (email == null) return false;
    final e = email.trim().toLowerCase();
    return e == createdByEmail || admins.contains(e);
  }

  int _cfgInt(String key, int fallback) {
    final v = notifConfig?[key];
    return v is num ? v.toInt() : fallback;
  }

  bool _cfgBool(String key, bool fallback) {
    final v = notifConfig?[key];
    return v is bool ? v : fallback;
  }

  bool get notifEnabled => _cfgBool('enabled', true);
  bool get notifTimeLimit => _cfgBool('timeLimit', true);
  int get notifStartHour => _cfgInt('startHour', 9);
  int get notifEndHour => _cfgInt('endHour', 21);
  int get notifMinCount => _cfgInt('minCount', 2);
  int get notifMaxCount => _cfgInt('maxCount', 5);
  int get notifMinNames => _cfgInt('minNames', 1);
  int get notifMaxNames => _cfgInt('maxNames', 3);

  Map<String, dynamic> toMap() => {
        'name': name,
        'code': code,
        'createdByEmail': createdByEmail,
        'createdByUsername': createdByUsername,
        'createdAt': createdAt.toIso8601String(),
        'admins': admins,
        if (photoBase64 != null) 'photoBase64': photoBase64,
        if (notifConfig != null) 'notifConfig': notifConfig,
      };

  factory Group.fromMap(String id, Map<String, dynamic> map) => Group(
        id: id,
        name: map['name'] as String? ?? '',
        code: map['code'] as String? ?? '',
        createdByEmail: map['createdByEmail'] as String? ?? '',
        createdByUsername: map['createdByUsername'] as String? ?? '',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        admins: (map['admins'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        photoBase64: map['photoBase64'] as String?,
        notifConfig: (map['notifConfig'] as Map?)?.cast<String, dynamic>(),
      );

  Group copyWith({
    String? name,
    List<String>? admins,
    String? photoBase64,
    Map<String, dynamic>? notifConfig,
  }) =>
      Group(
        id: id,
        name: name ?? this.name,
        code: code,
        createdByEmail: createdByEmail,
        createdByUsername: createdByUsername,
        createdAt: createdAt,
        admins: admins ?? this.admins,
        photoBase64: photoBase64 ?? this.photoBase64,
        notifConfig: notifConfig ?? this.notifConfig,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toMap(),
      };

  factory Group.fromJson(Map<String, dynamic> json) =>
      Group.fromMap(json['id'] as String, json);
}

class GroupMember {
  final String username;
  final String email;
  final DateTime joinedAt;

  /// Photo de profil (snapshot au moment de rejoindre), base64.
  final String? photoBase64;

  const GroupMember({
    required this.username,
    required this.email,
    required this.joinedAt,
    this.photoBase64,
  });

  Map<String, dynamic> toMap() => {
        'username': username,
        'email': email,
        'joinedAt': joinedAt.toIso8601String(),
        if (photoBase64 != null) 'photoBase64': photoBase64,
      };

  factory GroupMember.fromMap(Map<String, dynamic> map) => GroupMember(
        username: map['username'] as String? ?? '',
        email: map['email'] as String? ?? '',
        joinedAt: DateTime.tryParse(map['joinedAt'] as String? ?? '') ??
            DateTime.now(),
        photoBase64: map['photoBase64'] as String?,
      );
}
