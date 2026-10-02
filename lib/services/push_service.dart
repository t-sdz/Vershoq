import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../firebase_options.dart';
import 'group_service.dart';
import 'notification_service.dart';

/// Handler des messages reçus quand l'app est en arrière-plan / fermée.
/// Doit être une fonction top-level.
///
/// Android affiche DÉJÀ la notif (bloc notification du push, texte personnel
/// avec les prénoms) : ici on se contente d'armer l'alerte localement, sans
/// réseau ni Firestore.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Isolat séparé : enregistre les plugins avant toute utilisation.
  DartPluginRegistrant.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  try {
    // Cet isolat peut vivre longtemps : son cache SharedPreferences est
    // périmé (groupe changé depuis…). On relit le disque d'abord.
    await (await SharedPreferences.getInstance()).reload();
    final alert = PushService.parseAlert(message);
    if (alert == null) return;
    if (!await PushService.isForCurrentGroup(alert)) return;
    await NotificationService.upsertAlert(alert);
  } catch (e) {
    debugPrint('firebaseMessagingBackgroundHandler: $e');
  }
}

/// Notifications push (FCM) via le serveur externe.
///
/// Le serveur envoie, pour chaque alerte, UN message PAR MEMBRE sur le topic
/// personnel `u_<sha256(email)[0:40]>`, avec les prénoms propres à ce
/// membre. Plus aucun calcul de prénoms sur le téléphone.
class PushService {
  /// Appelé quand l'utilisateur TAPE une notif push (app en arrière-plan) :
  /// ouvre la caméra pour cette alerte.
  static void Function(String alertId)? onOpenAlert;

  /// Topic FCM personnel d'un membre : « u_ » + 40 premiers caractères hexa
  /// du SHA-256 de l'email normalisé (identique côté serveur).
  static String memberTopicFor(String email) {
    final digest = sha256.convert(utf8.encode(email.trim().toLowerCase()));
    return 'u_${digest.toString().substring(0, 40)}';
  }

  /// Transforme les données d'un push en alerte, ou null si ce n'est pas une
  /// alerte valide.
  static AlertMoment? parseAlert(RemoteMessage message) {
    final d = message.data;
    if (d['type']?.toString() != 'alert') return null;
    final id = d['alertId']?.toString() ?? '';
    final groupId = d['groupId']?.toString() ?? '';
    final sentAt = int.tryParse(d['sentAt']?.toString() ?? '');
    if (id.isEmpty || groupId.isEmpty || sentAt == null) return null;
    final cd = int.tryParse(d['cd']?.toString() ?? '') ?? 0;
    return AlertMoment(
      id: id,
      groupId: groupId,
      names: d['names']?.toString() ?? '',
      sentAtMs: sentAt,
      countdownSeconds: cd > 0 ? cd : 0,
    );
  }

  /// Vrai si l'alerte concerne le groupe ACTUEL (sinon ignorée).
  static Future<bool> isForCurrentGroup(AlertMoment alert) async {
    final current = await GroupService.getCurrentGroup();
    return current != null && current.id == alert.groupId;
  }

  static Future<void> init() async {
    if (kIsWeb) return;
    // Permission dans son propre try : un refus / une erreur ne doit pas
    // empêcher l'enregistrement des listeners.
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      debugPrint('PushService.requestPermission: $e');
    }
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // App au premier plan : Android n'affiche rien → on arme l'alerte et
      // on affiche la notif nous-mêmes.
      FirebaseMessaging.onMessage.listen((m) async {
        try {
          final alert = PushService.parseAlert(m);
          if (alert == null) return;
          if (!await isForCurrentGroup(alert)) return; // autre groupe
          final stored = await NotificationService.upsertAlert(alert);
          await NotificationService.showAlertNotification(
            stored,
            title: m.notification?.title,
            body: m.notification?.body,
          );
        } catch (e) {
          debugPrint('PushService.onMessage: $e');
        }
      });

      // Le jeton FCM du téléphone peut changer (mise à jour, réinstallation,
      // services Google…) : on se réabonne alors au topic personnel.
      FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        reconcileSubscriptions().catchError((_) {});
      });

      // App en arrière-plan puis on TAPE la notif système : ouvre la caméra.
      FirebaseMessaging.onMessageOpenedApp.listen((m) async {
        try {
          final alert = PushService.parseAlert(m);
          if (alert == null) return;
          await NotificationService.upsertAlert(alert);
          onOpenAlert?.call(alert.id);
        } catch (e) {
          debugPrint('PushService.onMessageOpenedApp: $e');
        }
      });
    } catch (e) {
      debugPrint('PushService.init: $e');
    }
  }

  /// Si l'app a été lancée (état tué) en tapant une notif push, arme l'alerte
  /// et renvoie son id. Sinon null. Aucun accès réseau.
  static Future<String?> initialTapAlert() async {
    if (kIsWeb) return null;
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg == null) return null;
      final alert = parseAlert(msg);
      if (alert == null) return null;
      await NotificationService.upsertAlert(alert);
      return alert.id;
    } catch (e) {
      debugPrint('PushService.initialTapAlert: $e');
      return null;
    }
  }

  /// Relit la dernière alerte du groupe courant dans Firestore (champ
  /// « lastAlert » écrit par le serveur) et l'arme localement si elle me
  /// concerne. Filet de sécurité quand la notif n'a pas pu être traitée en
  /// arrière-plan (Xiaomi qui bloque l'app, etc.) : ouvrir l'app suffit.
  static Future<void> syncLastAlert() async {
    if (kIsWeb) return;
    try {
      final group = await GroupService.getCurrentGroup();
      if (group == null) return;
      final email = (await GroupService.getCurrentUser())?.email ??
          FirebaseAuth.instance.currentUser?.email ??
          '';
      if (email.trim().isEmpty) return;
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(group.id)
          .get()
          .timeout(const Duration(seconds: 8));
      final last = doc.data()?['lastAlert'];
      if (last is! Map) return;
      final id = last['id']?.toString() ?? '';
      final sentAt = last['sentAt'];
      final cd = last['cd'];
      final names = last['names'];
      if (id.isEmpty || sentAt is! num || names is! Map) return;
      final mine = names[memberTopicFor(email)]?.toString() ?? '';
      if (mine.isEmpty) return; // alerte pas pour moi
      final alert = AlertMoment(
        id: id,
        groupId: group.id,
        names: mine,
        sentAtMs: sentAt.toInt(),
        countdownSeconds: cd is num && cd > 0 ? cd.toInt() : 0,
      );
      if (alert.isExpired()) return;
      await NotificationService.upsertAlert(alert);
    } catch (e) {
      debugPrint('PushService.syncLastAlert: $e');
    }
  }

  /// Noms COMPLETS des topics auxquels on est abonné.
  static const _subKey = 'vershoq_subscribed_topic_names';

  /// Ancien format : ids de groupes bruts (topics `group_<id>`).
  static const _legacySubKey = 'vershoq_subscribed_topics';
  static const _legacyMigratedKey = 'vershoq_group_topics_migrated';

  static Future<Set<String>> _subscribedSet() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_subKey) ?? const <String>[]).toSet();
  }

  static Future<void> _saveSubscribedSet(Set<String> s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_subKey, s.toList());
  }

  /// Se désabonne de l'ancien topic de groupe (plus utilisé par le serveur).
  static Future<void> unsubscribeGroup(String groupId) async {
    if (kIsWeb) return;
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('group_$groupId');
    } catch (_) {}
  }

  /// Migration unique : désabonne des anciens topics `group_<id>` (ceux
  /// mémorisés par l'ancien format + les groupes rejoints).
  static Future<void> _migrateLegacyGroupTopics() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_legacyMigratedKey) == true) return;
    final ids = <String>{
      ...(prefs.getStringList(_legacySubKey) ?? const <String>[]),
    };
    try {
      final joined = await GroupService.getJoinedGroups();
      ids.addAll(joined.map((j) => j.group.id));
    } catch (_) {}
    var ok = true;
    for (final id in ids) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic('group_$id');
      } catch (_) {
        ok = false;
      }
    }
    if (ok) {
      await prefs.remove(_legacySubKey);
      await prefs.setBool(_legacyMigratedKey, true);
    }
  }

  /// Réconcilie les abonnements FCM : un seul topic voulu, le topic personnel
  /// de l'utilisateur connecté. Se désabonne de tout autre topic mémorisé
  /// (ancien compte…). Appelé à chaque ouverture de l'app.
  static Future<void> reconcileSubscriptions() async {
    if (kIsWeb) return;
    await _migrateLegacyGroupTopics();
    final email = (await GroupService.getCurrentUser())?.email ??
        FirebaseAuth.instance.currentUser?.email ??
        '';
    final want = <String>{
      if (email.trim().isNotEmpty) memberTopicFor(email),
    };
    final have = await _subscribedSet();
    final kept = <String>{};
    for (final t in have.difference(want)) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic(t);
      } catch (_) {
        kept.add(t); // on réessaiera la prochaine fois
      }
    }
    for (final t in want) {
      // TOUJOURS (ré)abonner, même si on croit l'être déjà : l'abonnement est
      // lié au jeton FCM du téléphone, qui peut avoir changé sans qu'on le
      // sache. L'appel est sans effet si on est déjà abonné.
      try {
        await FirebaseMessaging.instance.subscribeToTopic(t);
        kept.add(t);
      } catch (_) {
        if (have.contains(t)) kept.add(t);
      }
    }
    await _saveSubscribedSet(kept);
  }

  /// Demande au serveur d'envoyer une alerte à TOUT le groupe (même app
  /// fermée). Le serveur calcule les prénoms de chacun et envoie un message
  /// par membre, puis renvoie combien de messages sont réellement partis.
  static Future<PushResult> sendGroupPush({required String groupId}) async {
    if (!AppConfig.pushEnabled) {
      return const PushResult.failed('serveur non configuré');
    }
    try {
      final res = await http.post(
        Uri.parse(AppConfig.pushServerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'secret': AppConfig.pushSecret,
          'groupId': groupId,
        }),
      );
      Map<String, dynamic> j = const {};
      try {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) j = d;
      } catch (_) {}
      int n(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
      if (res.statusCode == 200) {
        return PushResult.sent(n('sent'), n('total'));
      }
      if (res.statusCode == 409) return PushResult.busy(n('remaining'));
      if (j['error'] == 'no members') {
        return const PushResult.failed('pas assez de membres dans le groupe');
      }
      if (j['error'] == 'fcm') {
        final errs = j['errors'];
        final first =
            errs is List && errs.isNotEmpty ? errs.first.toString() : '';
        return PushResult.failed(
            'Firebase a refusé l\'envoi${first.isEmpty ? '' : ' ($first)'}');
      }
      return PushResult.failed('erreur serveur ${res.statusCode}');
    } catch (e) {
      debugPrint('PushService.sendGroupPush: $e');
      return const PushResult.failed('serveur injoignable');
    }
  }
}

/// Résultat d'une demande d'envoi au serveur.
class PushResult {
  final bool ok;

  /// Messages acceptés par Firebase / membres visés (si [ok]).
  final int sent;
  final int total;

  /// Secondes restantes de l'alerte en cours (> 0 = envoi refusé).
  final int busySeconds;

  /// Raison de l'échec (si ni [ok] ni [isBusy]).
  final String error;

  const PushResult.sent(this.sent, this.total)
      : ok = true,
        busySeconds = 0,
        error = '';
  const PushResult.failed([this.error = 'serveur injoignable'])
      : ok = false,
        sent = 0,
        total = 0,
        busySeconds = 0;
  const PushResult.busy(int seconds)
      : ok = false,
        sent = 0,
        total = 0,
        error = '',
        busySeconds = seconds < 1 ? 1 : seconds;

  bool get isBusy => busySeconds > 0;
}
