import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'notification_service.dart';

/// Handler des messages reçus quand l'app est en arrière-plan / fermée.
/// Doit être une fonction top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Chaque appareil calcule SES propres noms (les autres membres).
  // FCM affiche déjà la notification système ; on arme juste la bannière/caméra.
  final label = await NotificationService.buildMyMomentLabel();
  if (label != null) await NotificationService.registerRemoteMoment(label);
}

/// Notifications push (FCM) via le serveur externe (Deno Deploy).
class PushService {
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // App au premier plan : on affiche la notif + on arme la bannière.
      FirebaseMessaging.onMessage.listen((m) async {
        final label = await NotificationService.buildMyMomentLabel() ?? '';
        await NotificationService.registerRemoteMoment(label);
        await NotificationService.showRemote(
          "📸 Snap'It",
          label.isEmpty
              ? "C'est le moment !"
              : "Prends vite ta photo avec $label !",
          label,
        );
      });
    } catch (e) {
      debugPrint('PushService.init: $e');
    }
  }

  /// Abonne l'appareil aux notifications de ces groupes (topics FCM).
  static Future<void> subscribeGroups(List<String> groupIds) async {
    if (kIsWeb) return;
    for (final id in groupIds) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic('group_$id');
      } catch (_) {}
    }
  }

  static Future<void> unsubscribeGroup(String groupId) async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');
    } catch (_) {}
  }

  /// Demande au serveur d'envoyer une notif à TOUT le groupe (même app fermée).
  /// Renvoie true si le serveur a accepté.
  static Future<bool> sendGroupPush({
    required String groupId,
    String? label,
    String? title,
    String? body,
  }) async {
    if (!AppConfig.pushEnabled) return false;
    try {
      final res = await http.post(
        Uri.parse(AppConfig.pushServerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'secret': AppConfig.pushSecret,
          'groupId': groupId,
          if (label != null) 'label': label,
          if (title != null) 'title': title,
          if (body != null) 'body': body,
        }),
      );
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('PushService.sendGroupPush: $e');
      return false;
    }
  }
}
