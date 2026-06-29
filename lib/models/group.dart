class Group {
  final String id;
  final String name;
  final String code;
  final String createdByEmail;
  final String createdByUsername;
  final DateTime createdAt;

  /// Emails des administrateurs. Le créateur en fait toujours partie.
  final List<String> admins;

  const Group({
    required this.id,
    required this.name,
    required this.code,
    required this.createdByEmail,
    required this.createdByUsername,
    required this.createdAt,
    this.admins = const [],
  });

  /// Un email est admin s'il est dans la liste OU s'il est le créateur.
  bool isAdmin(String? email) {
    if (email == null) return false;
    final e = email.trim().toLowerCase();
    return e == createdByEmail || admins.contains(e);
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'code': code,
        'createdByEmail': createdByEmail,
        'createdByUsername': createdByUsername,
        'createdAt': createdAt.toIso8601String(),
        'admins': admins,
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

  const GroupMember({
    required this.username,
    required this.email,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
        'username': username,
        'email': email,
        'joinedAt': joinedAt.toIso8601String(),
      };

  factory GroupMember.fromMap(Map<String, dynamic> map) => GroupMember(
        username: map['username'] as String? ?? '',
        email: map['email'] as String? ?? '',
        joinedAt: DateTime.tryParse(map['joinedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
