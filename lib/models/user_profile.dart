class UserProfile {
  final String uid;
  final String name;
  final String username;
  final String email;
  final String? photoBase64;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    this.photoBase64,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'username': username,
        'email': email,
        if (photoBase64 != null) 'photoBase64': photoBase64,
      };

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) =>
      UserProfile(
        uid: uid,
        name: map['name'] as String? ?? '',
        username: map['username'] as String? ?? '',
        email: map['email'] as String? ?? '',
        photoBase64: map['photoBase64'] as String?,
      );

  UserProfile copyWith({
    String? name,
    String? username,
    String? photoBase64,
  }) =>
      UserProfile(
        uid: uid,
        name: name ?? this.name,
        username: username ?? this.username,
        email: email,
        photoBase64: photoBase64 ?? this.photoBase64,
      );
}
