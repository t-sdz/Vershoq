import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../models/group_photo_entry.dart';

class GroupPhotoService {
  static const _uuid = Uuid();

  static CollectionReference<Map<String, dynamic>> _photosCol(String groupId) =>
      FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('photos');

  static Future<String> uploadPhoto({
    required File file,
    required String groupId,
    required String personName,
    required String uploaderUsername,
    required String uploaderEmail,
  }) async {
    final id = _uuid.v4();
    final ref = FirebaseStorage.instance
        .ref()
        .child('groups/$groupId/photos/$id.jpg');

    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    await _photosCol(groupId).doc(id).set({
      'personName': personName,
      'uploaderUsername': uploaderUsername,
      'uploaderEmail': uploaderEmail,
      'remoteUrl': url,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return url;
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
    try {
      await FirebaseStorage.instance
          .ref()
          .child('groups/$groupId/photos/$photoId.jpg')
          .delete();
    } catch (_) {}
  }
}
