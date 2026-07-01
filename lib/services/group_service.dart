import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/group.dart';
import 'notification_service.dart';

/// Exception métier renvoyée au formulaire pour affichage utilisateur.
class GroupException implements Exception {
  final String message;
  GroupException(this.message);
  @override
  String toString() => message;
}

/// Un groupe rejoint par l'utilisateur, avec ses propres identifiants dans
/// ce groupe.
class JoinedGroup {
  final Group group;
  final GroupMember member;
  const JoinedGroup(this.group, this.member);
}

class GroupService {
  static const _currentGroupKey = 'vershoq_current_group';
  static const _currentUserKey = 'vershoq_current_user';
  static const _memberNamesKey = 'vershoq_member_names';
  static const _joinedGroupsKey = 'vershoq_joined_groups';

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
      final creatorEmail = email.trim().toLowerCase();
      final docRef = await _groups.add({
        'name': name.trim(),
        'code': code,
        'createdByEmail': creatorEmail,
        'createdByUsername': username.trim(),
        'createdAt': now.toIso8601String(),
        'memberCount': 1,
        'admins': [creatorEmail],
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
        createdByEmail: creatorEmail,
        createdByUsername: username.trim(),
        createdAt: now,
        admins: [creatorEmail],
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
  // Administration du groupe
  // ---------------------------------------------------------------------------

  /// Renomme le groupe (réservé aux admins côté UI).
  static Future<void> renameGroup(String groupId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw GroupException('Le nom du groupe est requis.');
    if (trimmed.length > 60) {
      throw GroupException('Nom trop long (60 caractères max).');
    }
    try {
      await _groups.doc(groupId).update({'name': trimmed});
      final current = await getCurrentGroup();
      if (current != null && current.id == groupId) {
        await _saveGroupLocal(Group(
          id: current.id,
          name: trimmed,
          code: current.code,
          createdByEmail: current.createdByEmail,
          createdByUsername: current.createdByUsername,
          createdAt: current.createdAt,
          admins: current.admins,
        ));
      }
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  /// Promeut un membre administrateur du groupe.
  static Future<void> addAdmin(String groupId, String memberEmail) async {
    try {
      await _groups.doc(groupId).update({
        'admins': FieldValue.arrayUnion([memberEmail.trim().toLowerCase()]),
      });
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  /// Retire les droits d'administrateur d'un membre.
  static Future<void> removeAdmin(String groupId, String memberEmail) async {
    try {
      await _groups.doc(groupId).update({
        'admins': FieldValue.arrayRemove([memberEmail.trim().toLowerCase()]),
      });
    } on FirebaseException catch (e) {
      throw GroupException('Erreur Firebase : ${e.message ?? e.code}');
    }
  }

  /// Recharge le groupe courant depuis Firestore (nom + admins à jour) et
  /// met à jour le cache local. Retombe sur le cache local en cas d'erreur.
  static Future<Group?> refreshCurrentGroup() async {
    final local = await getCurrentGroup();
    if (local == null) return null;
    try {
      final doc = await _groups.doc(local.id).get();
      if (doc.exists && doc.data() != null) {
        final fresh = Group.fromMap(doc.id, doc.data()!);
        await _saveGroupLocal(fresh);
        return fresh;
      }
    } catch (_) {}
    return local;
  }

  // ---------------------------------------------------------------------------
  // Groupes rejoints (multi-groupes) + groupe actif
  // ---------------------------------------------------------------------------

  /// Liste des groupes rejoints. Migre automatiquement l'ancien format
  /// (groupe unique) vers la liste au premier accès.
  static Future<List<JoinedGroup>> getJoinedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_joinedGroupsKey);
    final list = <JoinedGroup>[];
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          final m = e as Map<String, dynamic>;
          list.add(JoinedGroup(
            Group.fromJson(m['group'] as Map<String, dynamic>),
            GroupMember.fromMap(m['member'] as Map<String, dynamic>),
          ));
        }
      } catch (_) {}
    }
    if (list.isEmpty) {
      // Migration depuis l'ancien format (un seul groupe).
      final g = await getCurrentGroup();
      final u = await getCurrentUser();
      if (g != null && u != null) {
        list.add(JoinedGroup(g, u));
        await _writeJoined(list);
      }
    }
    return list;
  }

  static Future<void> _writeJoined(List<JoinedGroup> list) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = list
        .map((j) => {'group': j.group.toJson(), 'member': j.member.toMap()})
        .toList();
    await prefs.setString(_joinedGroupsKey, jsonEncode(arr));
  }

  /// Change le groupe actif (celui affiché dans le feed) et replanifie les
  /// notifications pour ce groupe.
  static Future<void> setActiveGroup(String groupId) async {
    final list = await getJoinedGroups();
    JoinedGroup? target;
    for (final j in list) {
      if (j.group.id == groupId) target = j;
    }
    if (target == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentGroupKey, jsonEncode(target.group.toJson()));
    await prefs.setString(_currentUserKey, jsonEncode(target.member.toMap()));
    await prefs.remove(_memberNamesKey);
    await NotificationService.cancelAll();
    await NotificationService.scheduleRandom();
  }

  // ---------------------------------------------------------------------------
  // Persistance locale du groupe courant
  // ---------------------------------------------------------------------------
  static Future<void> _saveLocal(Group group, GroupMember member) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentGroupKey, jsonEncode(group.toJson()));
    await prefs.setString(_currentUserKey, jsonEncode(member.toMap()));
    // Ajoute (ou met à jour) dans la liste des groupes rejoints.
    final list = await getJoinedGroups();
    final idx = list.indexWhere((j) => j.group.id == group.id);
    if (idx >= 0) {
      list[idx] = JoinedGroup(group, member);
    } else {
      list.add(JoinedGroup(group, member));
    }
    await _writeJoined(list);
  }

  static Future<void> _saveGroupLocal(Group group) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentGroupKey, jsonEncode(group.toJson()));
    // Met à jour l'entrée correspondante dans la liste des groupes rejoints.
    final list = await getJoinedGroups();
    final idx = list.indexWhere((j) => j.group.id == group.id);
    if (idx >= 0) {
      list[idx] = JoinedGroup(group, list[idx].member);
      await _writeJoined(list);
    }
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

  /// Quitte un groupe. Sans argument, quitte le groupe actif. S'il restait
  /// d'autres groupes, bascule automatiquement sur le premier.
  static Future<void> leaveGroup([String? groupId]) async {
    final prefs = await SharedPreferences.getInstance();
    final active = await getCurrentGroup();
    final targetId = groupId ?? active?.id;
    if (targetId == null) return;

    var list = await getJoinedGroups();
    list = list.where((j) => j.group.id != targetId).toList();
    await _writeJoined(list);

    // Si on a quitté le groupe actif, on bascule sur un autre (ou aucun).
    if (active == null || active.id == targetId) {
      if (list.isNotEmpty) {
        await prefs.setString(
            _currentGroupKey, jsonEncode(list.first.group.toJson()));
        await prefs.setString(
            _currentUserKey, jsonEncode(list.first.member.toMap()));
      } else {
        await prefs.remove(_currentGroupKey);
        await prefs.remove(_currentUserKey);
      }
      await prefs.remove(_memberNamesKey);
    }

    // Annule les notifications de l'ancien groupe et replanifie pour le
    // nouveau groupe actif (ou rien s'il n'y en a plus).
    await NotificationService.cancelAll();
    await NotificationService.scheduleRandom();
  }

  static Future<void> cacheMemberNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_memberNamesKey, names);
  }

  static Future<List<String>> getCachedMemberNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_memberNamesKey) ?? [];
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
