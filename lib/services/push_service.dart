import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../firebase_options.dart';
import 'group_service.dart';
import 'notification_service.dart';

/// Rafraîchit, depuis Firestore (source unique de vérité), la config du groupe
/// (dont les prénoms ajoutés par l'admin) ET la liste des membres, juste avant
/// de calculer l'appariement. Ainsi TOUS les téléphones partent de la MÊME
/// liste → mêmes groupes → réciprocité garantie (Tess↔Max). Ignoré si
/// hors-ligne (on garde alors le cache).
Future<void> _refreshGroupQuietly() async {
  try {
    final g = await GroupService.refreshCurrentGroup();
    if (g != null) {
      final members = await GroupService.getMembers(g.id);
      await GroupService.cacheMemberNames(
          members.map((m) => m.username).toList());
    }
  } catch (_) {}
}

/// Handler des messages reçus quand l'app est en arrière-plan / fermée.
/// Doit être une fonction top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Cet isolat est séparé de l'app : il faut initialiser Firebase ici pour
  // pouvoir relire la liste des membres depuis Firestore.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  // Ignore les pushes d'un autre groupe (ex : groupe quitté encore abonné).
  if (!await _isForCurrentGroup(message)) return;
  // On repart de la MÊME liste que les autres téléphones (source Firestore) →
  // mêmes groupes → réciprocité. Chaque appareil calcule ensuite SES noms à
  // partir de la graine commune.
  await _refreshGroupQuietly();
  try {
    final label =
        await NotificationService.buildMyMomentLabel(seed: _seedOf(message)) ??
            '';
    await NotificationService.registerRemoteMoment(label);
  } catch (e) {
    debugPrint('firebaseMessagingBackgroundHandler: $e');
  }
}

/// Lit la graine commune (data.seed) d'un push, ou null si absente.
int? _seedOf(RemoteMessage message) {
  final raw = message.data['seed'];
  if (raw == null) return null;
  return int.tryParse(raw.toString());
}

/// Vrai si le push concerne le groupe ACTUEL. Un push d'un AUTRE groupe (ex :
/// un groupe qu'on a quitté mais dont l'abonnement FCM traîne encore) est
/// ignoré → plus de mélange avec l'ancien groupe.
Future<bool> _isForCurrentGroup(RemoteMessage message) async {
  final gid = message.data['groupId']?.toString();
  if (gid == null || gid.isEmpty) return true; // pas d'info : on laisse passer
  final current = await GroupService.getCurrentGroup();
  return current != null && current.id == gid;
}

/// Notifications push (FCM) via le serveur externe (Deno Deploy).
class PushService {
  /// Appelé quand l'utilisateur TAPE une notif push (ouvre la caméra).
  static void Function(String label)? onOpen;

  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // App au premier plan : on affiche la notif + on arme la bannière.
      FirebaseMessaging.onMessage.listen((m) async {
        if (!await _isForCurrentGroup(m)) return; // autre groupe → ignore
        await _refreshGroupQuietly();
        final label =
            await NotificationService.buildMyMomentLabel(seed: _seedOf(m)) ?? '';
        await NotificationService.registerRemoteMoment(label);
        await NotificationService.showRemote(
          "📸 Snap'It",
          label.isEmpty
              ? "C'est le moment !"
              : "Prends vite ta photo avec $label !",
          label,
        );
      });

      // App en arrière-plan puis on TAPE la notif système : ouvre la caméra.
      FirebaseMessaging.onMessageOpenedApp.listen((m) async {
        if (!await _isForCurrentGroup(m)) return; // autre groupe → ignore
        await _refreshGroupQuietly();
        final label =
            await NotificationService.buildMyMomentLabel(seed: _seedOf(m)) ?? '';
        await NotificationService.registerRemoteMoment(label);
        onOpen?.call(label);
      });
    } catch (e) {
      debugPrint('PushService.init: $e');
    }
  }

  /// Si l'app a été lancée (état tué) en tapant une notif push, renvoie le
  /// label du moment (les prénoms). Sinon null.
  static Future<String?> initialTapLabel() async {
    if (kIsWeb) return null;
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg == null) return null;
      if (!await _isForCurrentGroup(msg)) return null; // autre groupe → ignore
      await _refreshGroupQuietly();
      final label =
          await NotificationService.buildMyMomentLabel(seed: _seedOf(msg)) ?? '';
      await NotificationService.registerRemoteMoment(label);
      return label;
    } catch (e) {
      debugPrint('PushService.initialTapLabel: $e');
      return null;
    }
  }

  static const _subKey = 'vershoq_subscribed_topics';

  static Future<Set<String>> _subscribedSet() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_subKey) ?? const <String>[]).toSet();
  }

  static Future<void> _saveSubscribedSet(Set<String> s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_subKey, s.toList());
  }

  /// Abonne l'appareil aux notifications de ces groupes (topics FCM).
  static Future<void> subscribeGroups(List<String> groupIds) async {
    if (kIsWeb) return;
    final set = await _subscribedSet();
    for (final id in groupIds) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic('group_$id');
        set.add(id);
      } catch (_) {}
    }
    await _saveSubscribedSet(set);
  }

  static Future<void> unsubscribeGroup(String groupId) async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');
    } catch (_) {}
    final set = await _subscribedSet();
    set.remove(groupId);
    await _saveSubscribedSet(set);
  }

  /// Réconcilie les abonnements FCM avec les groupes réellement rejoints : se
  /// désabonne des topics en trop (ex : un groupe quitté dont le désabonnement
  /// avait échoué) et s'abonne aux manquants. À appeler à l'ouverture du fil.
  static Future<void> reconcileSubscriptions(List<String> currentGroupIds) async {
    if (kIsWeb) return;
    final want = currentGroupIds.toSet();
    final have = await _subscribedSet();
    for (final id in have.difference(want)) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic('group_$id');
      } catch (_) {}
    }
    for (final id in want.difference(have)) {
      try {
        await FirebaseMessaging.instance.subscribeToTopic('group_$id');
      } catch (_) {}
    }
    await _saveSubscribedSet(want);
  }

  /// Demande au serveur d'envoyer une notif à TOUT le groupe (même app fermée).
  /// Renvoie true si le serveur a accepté.
  static Future<bool> sendGroupPush({
    required String groupId,
    int? seed,
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
          if (seed != null) 'seed': seed,
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
