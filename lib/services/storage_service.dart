import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/photo_entry.dart';
import 'group_photo_service.dart';
import 'group_service.dart';

class StorageService {
  static const _entriesKey = 'vershoq_photo_entries';
  static const _uuid = Uuid();

  static Future<Directory> _photosDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${dir.path}/vershoq_photos');
    await photosDir.create(recursive: true);
    return photosDir;
  }

  static Future<PhotoEntry> savePhoto({
    required File photoFile,
    required String personName,
  }) async {
    final dir = await _photosDir();
    final id = _uuid.v4();
    final destPath = '${dir.path}/$id.jpg';
    await photoFile.copy(destPath);

    final entry = PhotoEntry(
      id: id,
      personName: personName,
      localPath: destPath,
      timestamp: DateTime.now(),
    );

    await _appendEntry(entry);

    // Upload to shared group gallery in background (fire-and-forget)
    _uploadToGroup(photoFile, personName).ignore();

    return entry;
  }

  static Future<void> _uploadToGroup(File file, String personName) async {
    try {
      final group = await GroupService.getCurrentGroup();
      final user = await GroupService.getCurrentUser();
      if (group == null || user == null) return;
      await GroupPhotoService.uploadPhoto(
        file: file,
        groupId: group.id,
        personName: personName,
        uploaderUsername: user.username,
        uploaderEmail: user.email,
      );
    } catch (_) {}
  }

  static Future<void> _appendEntry(PhotoEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_entriesKey) ?? [];
    list.add(jsonEncode(entry.toJson()));
    await prefs.setStringList(_entriesKey, list);
  }

  static Future<List<PhotoEntry>> getEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_entriesKey) ?? [];
    final entries = list
        .map((s) => PhotoEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    // newest first
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  static Future<void> deleteEntry(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_entriesKey) ?? [];
    list.removeWhere((s) {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return map['id'] == id;
    });
    await prefs.setStringList(_entriesKey, list);

    // Also delete the local file
    final dir = await _photosDir();
    final file = File('${dir.path}/$id.jpg');
    if (await file.exists()) await file.delete();
  }
}
