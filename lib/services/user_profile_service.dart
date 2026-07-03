import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'auth_service.dart';

class UserProfileService {
  static const _cacheKey = 'vershoq_user_profile';

  static CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  static Future<UserProfile> createProfile({
    required String uid,
    required String name,
    required String username,
    required String email,
  }) async {
    final profile = UserProfile(
      uid: uid,
      name: name.trim(),
      username: username.trim(),
      email: email.trim().toLowerCase(),
    );
    await _users.doc(uid).set(profile.toMap());
    await _cache(profile);
    return profile;
  }

  /// Crée le profil s'il n'existe pas (cas d'une 1re connexion Google).
  static Future<UserProfile> ensureProfile({
    required String uid,
    required String email,
    String? displayName,
  }) async {
    final existing = await fetchProfile(uid);
    if (existing != null) return existing;
    final name = (displayName ?? '').trim();
    final base = name.isNotEmpty ? name : email.split('@').first;
    final username = base.split(' ').first;
    return createProfile(
      uid: uid,
      name: name.isNotEmpty ? name : username,
      username: username,
      email: email,
    );
  }

  static Future<UserProfile?> fetchProfile(String uid) async {
    try {
      final doc = await _users.doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      final profile = UserProfile.fromMap(uid, doc.data()!);
      await _cache(profile);
      return profile;
    } catch (_) {
      return getCachedProfile();
    }
  }

  static Future<void> updateProfile(UserProfile profile) async {
    await _users.doc(profile.uid).update(profile.toMap());
    await _cache(profile);
  }

  /// Compresse et met à jour la photo de profil (base64, comme les photos
  /// du groupe pour rester sur le plan Firebase gratuit).
  static Future<UserProfile> updatePhoto(UserProfile profile, File file) async {
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 400,
      minHeight: 400,
      quality: 70,
      keepExif: false,
    );
    if (compressed == null) return profile;
    final updated = profile.copyWith(photoBase64: base64Encode(compressed));
    await updateProfile(updated);
    return updated;
  }

  static Future<void> _cache(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode({'uid': profile.uid, ...profile.toMap()}));
  }

  static Future<UserProfile?> getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserProfile.fromMap(map['uid'] as String, map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  /// Charge le profil courant : cache d'abord (rapide), puis rafraîchit
  /// depuis Firestore si un utilisateur est connecté.
  static Future<UserProfile?> current() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return null;
    final fresh = await fetchProfile(uid);
    return fresh ?? getCachedProfile();
  }
}
