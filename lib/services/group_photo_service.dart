import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

import '../models/group_photo_entry.dart';

class GroupPhotoService {
  static const _uuid = Uuid();

  static CollectionReference<Map<String, dynamic>> _photosCol(String groupId) =>
      FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('photos');

  /// Compresses image and uploads as base64 to Firestore.
  static Future<void> uploadPhoto({
    required File file,
    required String groupId,
    required String personName,
    required String uploaderUsername,
    required String uploaderEmail,
    String? challenge,
  }) async {
    // Compress to max 720px wide, quality 60 → typically 30-80 KB
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 720,
      minHeight: 720,
      quality: 60,
      keepExif: false,
    );
    if (compressed == null) return;

    final base64str = base64Encode(compressed);
    final id = _uuid.v4();

    await _photosCol(groupId).doc(id).set({
      'personName': personName,
      'uploaderUsername': uploaderUsername,
      'uploaderEmail': uploaderEmail,
      'imageBase64': base64str,
      'timestamp': DateTime.now().toIso8601String(),
      if (challenge != null && challenge.isNotEmpty) 'challenge': challenge,
    });
  }

  /// Récupère une fois (sans écoute live) les photos d'un groupe — utile pour
  /// agréger plusieurs groupes dans une galerie perso globale.
  static Future<List<GroupPhotoEntry>> fetchGroupPhotos(String groupId,
      {int limit = 50}) async {
    final snap = await _photosCol(groupId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => GroupPhotoEntry.fromMap(d.id, d.data()))
        .toList();
  }

  /// Fil du groupe. On limite le nombre de photos chargées pour économiser le
  /// quota Firebase gratuit (chaque photo lue = 1 lecture facturée) et la
  /// mémoire (les images sont stockées en base64 dans le document).
  static Stream<List<GroupPhotoEntry>> streamGroupPhotos(String groupId,
      {int limit = 30}) {
    return _photosCol(groupId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GroupPhotoEntry.fromMap(d.id, d.data()))
            .toList());
  }

  static Future<void> deletePhoto(String groupId, String photoId) async {
    await _photosCol(groupId).doc(photoId).delete();
  }
}
