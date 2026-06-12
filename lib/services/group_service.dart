import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/group.dart';

class GroupException implements Exception {
  final String message;
  GroupException(this.message);
  @override
  String toString() => message;
}

class GroupService {
  static const _currentGroupKey  = 'vershoq_current_group';
  static const _currentUserKey   = 'vershoq_current_user';
  static const _memberNamesKey   = 'vershoq_member_names';

  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  // ── Auth helper ─────────────────────────────────────────────────────────────
  static User _requireAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw GroupException('Tu dois être connecté.');
    return user;
  }

  // ── Création ─────────────────────────────────────────────────────────────────
  static Future<Group> createGroup({
    required String name,
    required String username,
  }) async {
    final authUser = _requireAuth();
    _validateFields(name: name, username: username);

    final code = await _generateUniqueCode();
    final now  = DateTime.now();
    final email = authUser.email ?? '';
    final uid   = authUser.uid;

    try {
      final docRef = await _groups.add({
        'name': name.trim(),
        'code': code,
        'createdByEmail': email,
        'createdByUsername': username.trim(),
        'createdByUid': uid,
        'createdAt': now.toIso8601String(),
        'memberCount': 1,
      });

      final member = GroupMember(
        uid: uid,
        username: username.trim(),
        email: email,
        joinedAt: now,
      );
      await docRef.collection('members').add(member.toMap());

      final group = Group(
        id: docRef.id,
        name: name.trim(),
        code: code,
        createdByEmail: email,
        createdByUsername: username.trim(),
        createdByUid: uid,
        createdAt: now,
      );

      await _saveLocal(group, member);
      return group;
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  // ── Rejoindre ────────────────────────────────────────────────────────────────
  static Future<Group> joinGroup({
    required String code,
    required String username,
  }) async {
    final authUser = _requireAuth();
    _validateFields(username: username);

    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.length < 4) {
      throw GroupException('Code de groupe invalide.');
    }

    final email = authUser.email ?? '';
    final uid   = authUser.uid;

    try {
      final snap = await _groups
          .where('code', isEqualTo: normalizedCode)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        throw GroupException('Aucun groupe ne correspond à ce code.');
      }

      final doc   = snap.docs.first;
      final group = Group.fromMap(doc.id, doc.data());
      final now   = DateTime.now();
      final member = GroupMember(
        uid: uid,
        username: username.trim(),
        email: email,
        joinedAt: now,
      );

      // Évite les doublons par UID
      final existing = await doc.reference
          .collection('members')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (existing.docs.isEmpty) {
        await doc.reference.collection('members').add(member.toMap());
        await doc.reference.update({'memberCount': FieldValue.increment(1)});
      }

      await _saveLocal(group, member);
      return group;
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  // ── Membres ──────────────────────────────────────────────────────────────────
  static Future<List<GroupMember>> getMembers(String groupId) async {
    final snap = await _groups.doc(groupId).collection('members').get();
    return snap.docs.map((d) => GroupMember.fromMap(d.data())).toList();
  }

  static Future<void> removeMember(String groupId, String memberUid) async {
    final authUser = _requireAuth();

    // Vérifie que l'appelant est bien le créateur du groupe
    final groupDoc = await _groups.doc(groupId).get();
    final createdByUid = groupDoc.data()?['createdByUid'] as String? ?? '';
    if (createdByUid != authUser.uid) {
      throw GroupException('Seul l\'admin peut supprimer un membre.');
    }

    // Empêche l'admin de se supprimer lui-même
    if (memberUid == authUser.uid) {
      throw GroupException('Tu ne peux pas te supprimer toi-même.');
    }

    try {
      final snap = await _groups
          .doc(groupId)
          .collection('members')
          .where('uid', isEqualTo: memberUid)
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

  // ── Persistance locale ───────────────────────────────────────────────────────
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
    await prefs.remove(_memberNamesKey);
  }

  static Future<void> cacheMemberNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_memberNamesKey, names);
  }

  static Future<List<String>> getCachedMemberNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_memberNamesKey) ?? [];
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  static Future<String> _generateUniqueCode() async {
    final random = Random.secure();
    for (int i = 0; i < 10; i++) {
      final code = List.generate(
        6,
        (_) => _codeChars[random.nextInt(_codeChars.length)],
      ).join();
      final exists = await _groups.where('code', isEqualTo: code).limit(1).get();
      if (exists.docs.isEmpty) return code;
    }
    throw GroupException('Impossible de générer un code unique, réessaie.');
  }

  static void _validateFields({String? name, String? username}) {
    if (name != null && name.trim().isEmpty) {
      throw GroupException('Le nom du groupe est requis.');
    }
    if (username != null && username.trim().isEmpty) {
      throw GroupException('Le nom d\'utilisateur est requis.');
    }
  }
}
