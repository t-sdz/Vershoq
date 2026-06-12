import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/group.dart';

/// Exception métier renvoyée au formulaire pour affichage utilisateur.
class GroupException implements Exception {
  final String message;
  GroupException(this.message);
  @override
  String toString() => message;
}

class GroupService {
  static const _currentGroupKey = 'vershoq_current_group';
  static const _currentUserKey = 'vershoq_current_user';

  // Caractères sans ambiguïté (pas de O/0, I/1)
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  // ---------------------------------------------------------------------------
  // Création
  // ---------------------------------------------------------------------------
  static Future<Group> createGroup({
    required String name,
    required String username,
    required String email,
  }) async {
    _validate(name: name, username: username, email: email);

    final code = await _generateUniqueCode();
    final now = DateTime.now();

    try {
      final docRef = await _groups.add({
        'name': name.trim(),
        'code': code,
        'createdByEmail': email.trim().toLowerCase(),
        'createdByUsername': username.trim(),
        'createdAt': now.toIso8601String(),
        'memberCount': 1,
      });

      final member = GroupMember(
        username: username.trim(),
        email: email.trim().toLowerCase(),
        joinedAt: now,
      );
      await docRef.collection('members').add(member.toMap());

      final group = Group(
        id: docRef.id,
        name: name.trim(),
        code: code,
        createdByEmail: email.trim().toLowerCase(),
        createdByUsername: username.trim(),
        createdAt: now,
      );

      await _saveLocal(group, member);
      return group;
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  // ---------------------------------------------------------------------------
  // Rejoindre
  // ---------------------------------------------------------------------------
  static Future<Group> joinGroup({
    required String code,
    required String username,
    required String email,
  }) async {
    _validate(username: username, email: email);
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.length < 4) {
      throw GroupException('Code de groupe invalide.');
    }

    try {
      final snap = await _groups
          .where('code', isEqualTo: normalizedCode)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        throw GroupException('Aucun groupe ne correspond à ce code.');
      }

      final doc = snap.docs.first;
      final group = Group.fromMap(doc.id, doc.data());
      final now = DateTime.now();
      final member = GroupMember(
        username: username.trim(),
        email: email.trim().toLowerCase(),
        joinedAt: now,
      );

      // Évite les doublons : un même email ne rejoint qu'une fois
      final existing = await doc.reference
          .collection('members')
          .where('email', isEqualTo: member.email)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        await doc.reference.collection('members').add(member.toMap());
        await doc.reference.update({
          'memberCount': FieldValue.increment(1),
        });
      }

      await _saveLocal(group, member);
      return group;
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  // ---------------------------------------------------------------------------
  // Membres
  // ---------------------------------------------------------------------------
  static Future<List<GroupMember>> getMembers(String groupId) async {
    final snap = await _groups.doc(groupId).collection('members').get();
    return snap.docs.map((d) => GroupMember.fromMap(d.data())).toList();
  }

  static Future<void> removeMember(String groupId, String memberEmail) async {
    try {
      final snap = await _groups
          .doc(groupId)
          .collection('members')
          .where('email', isEqualTo: memberEmail)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.delete();
        await _groups.doc(groupId).update({
          'memberCount': FieldValue.increment(-1),
        });
      }
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  // ---------------------------------------------------------------------------
  // Persistance locale du groupe courant
  // ---------------------------------------------------------------------------
  static Future<void> _saveLocal(Group group, GroupMember member) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentGroupKey, jsonEncode(group.toJson()));
    await prefs.setString(_currentUserKey, jsonEncode(member.toMap()));
  }

  static Future<Group?> getCurrentGroup() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentGroupKey);
    if (raw == null) return null;
    try {
      return Group.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<GroupMember?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_currentUserKey);
    if (raw == null) return null;
    try {
      return GroupMember.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> leaveGroup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentGroupKey);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static Future<String> _generateUniqueCode() async {
    final random = Random.secure();
    for (int attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(
        6,
        (_) => _codeChars[random.nextInt(_codeChars.length)],
      ).join();

      final exists =
          await _groups.where('code', isEqualTo: code).limit(1).get();
      if (exists.docs.isEmpty) return code;
    }
    // Repli extrêmement improbable
    throw GroupException('Impossible de générer un code unique, réessaie.');
  }

  static void _validate({String? name, String? username, String? email}) {
    if (name != null && name.trim().isEmpty) {
      throw GroupException('Le nom du groupe est requis.');
    }
    if (username != null && username.trim().isEmpty) {
      throw GroupException('Le nom d\'utilisateur est requis.');
    }
    if (email != null) {
      final e = email.trim();
      final valid = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(e);
      if (!valid) throw GroupException('Adresse email invalide.');
    }
  }
}
