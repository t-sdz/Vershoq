import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
      'uploaderUid': uid,
      'imageBase64': base64str,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Stream<List<GroupPhotoEntry>> streamGroupPhotos(String groupId) {
    return _photosCol(groupId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GroupPhotoEntry.fromMap(d.id, d.data()))
            .toList());
  }

  static Future<void> deletePhoto(String groupId, String photoId) async {
    await _photosCol(groupId).doc(photoId).delete();
  }
}
