import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../models/group.dart';
import 'group_service.dart';

// Must be top-level for the background isolate
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {}

/// Une alerte photo (« moment »), reçue par push ou planifiée localement.
/// Tout est relatif à [sentAtMs] (heure d'envoi par le serveur) → même
/// deadline pour tout le groupe, quel que soit le moment où on ouvre l'app.
class AlertMoment {
  /// Identifiant unique de l'alerte (alertId du serveur). Une photo par id.
  final String id;
  final String groupId;

  /// Prénoms à photographier pour CET utilisateur (« A, B et C »).
  final String names;

  /// Heure d'envoi (ms depuis epoch).
  final int sentAtMs;

  /// Durée du compte à rebours en secondes (0 = pas de compte à rebours).
  final int countdownSeconds;

  /// Sans compte à rebours, une alerte reste valable 6 h.
  static const noCountdownValidityMs = 6 * 60 * 60 * 1000;

  const AlertMoment({
    required this.id,
    required this.groupId,
    required this.names,
    required this.sentAtMs,
    this.countdownSeconds = 0,
  });

  bool get hasCountdown => countdownSeconds > 0;

  int get deadlineMs => hasCountdown
      ? sentAtMs + countdownSeconds * 1000
      : sentAtMs + noCountdownValidityMs;

  /// Temps restant (horloge murale, donc pas de dérive), jamais négatif.
  Duration remaining([int? nowMs]) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final ms = deadlineMs - now;
    return Duration(milliseconds: ms > 0 ? ms : 0);
  }

  bool isExpired([int? nowMs]) =>
      (nowMs ?? DateTime.now().millisecondsSinceEpoch) >= deadlineMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'g': groupId,
        'l': names,
        't': sentAtMs,
        'cd': countdownSeconds,
      };

  /// Renvoie null si l'entrée est invalide (ex : ancien format sans id).
  static AlertMoment? fromJson(dynamic e) {
    if (e is! Map) return null;
    final id = e['id'];
    final t = e['t'];
    if (id is! String || id.isEmpty || t is! num) return null;
    final cd = e['cd'];
    return AlertMoment(
      id: id,
      groupId: e['g']?.toString() ?? '',
      names: e['l']?.toString() ?? '',
      sentAtMs: t.toInt(),
      countdownSeconds: cd is num ? cd.toInt() : 0,
    );
  }
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String payload)? _onTap;

  /// Incrémenté chaque fois qu'un moment est armé ou consommé (push reçu app
  /// ouverte, photo prise…). Le feed l'écoute pour mettre à jour la bannière.
  static final ValueNotifier<int> momentTick = ValueNotifier<int>(0);

  static const _channelId = 'vershoq_shots';
  static const _channelName = 'Photos spontanées';
  static const _captureActionId = 'vershoq_capture';
  static const _iosCategoryId = 'vershoq_shot_category';

  /// Liste des alertes (nouveau format, liée à un alertId).
  static const _alertsKey = 'vershoq_alerts';

  /// Ensemble des alertId déjà consommés (photo prise).
  static const _consumedAlertsKey = 'vershoq_alerts_consumed';

  // Anciennes clés (format sans alertId) : effacées au nettoyage.
  static const _legacyMomentsKey = 'vershoq_moments';
  static const _legacyConsumedSetKey = 'vershoq_moments_consumed_set';

  /// On garde les alertes 24 h (une alerte sans chrono dure 6 h max).
  static const _pruneAfterMs = 24 * 60 * 60 * 1000;

  /// Tolérance de décalage d'horloge entre le serveur et le téléphone.
  static const _clockSkewMs = 2 * 60 * 1000;

  static const _payloadPrefix = 'alert:';

  /// Payload d'une notif liée à une alerte.
  static String payloadFor(String alertId) => '$_payloadPrefix$alertId';

  /// Extrait l'alertId d'un payload `alert:<id>`, sinon null.
  static String? alertIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(_payloadPrefix)) return null;
    final id = payload.substring(_payloadPrefix.length);
    return id.isEmpty ? null : id;
  }

  /// Id de notification stable (entier positif) dérivé de l'alertId.
  static int notifIdFor(String alertId) => alertId.hashCode & 0x7fffffff;

  static Future<void> init({
    required void Function(String payload) onTap,
  }) async {
    // Pas de notifications locales sur navigateur : on ignore tout pour ne
    // pas faire planter l'app au démarrage sur le web.
    if (kIsWeb) return;
    _onTap = onTap;

    tz.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Fallback to UTC if timezone detection fails
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          _iosCategoryId,
          actions: [
            DarwinNotificationAction.plain(
              _captureActionId,
              '📸 Capturer maintenant',
              options: {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        // « alert:<id> » → caméra pour cette alerte ; ancien payload (prénoms)
        // → caméra « libre » (comportement historique).
        _onTap?.call(response.payload ?? '');
      },
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );

    // Request Android 13+ permission
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    // Crée explicitement le canal pour que les push Firebase (reçus quand
    // l'app est fermée) aient un canal existant à utiliser, sinon Android les
    // ignore silencieusement.
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifications pour prendre une photo avec le groupe',
        importance: Importance.max,
      ),
    );
  }

  /// Returns the notification payload if the app was launched by tapping one.
  static Future<String?> getLaunchPayload() async {
    if (kIsWeb) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      // Lancée en tapant une notif : on renvoie le payload (éventuellement
      // vide, mais jamais null).
      return details?.notificationResponse?.payload ?? '';
    }
    return null;
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  // Compte à rebours : réglage du GROUPE (fixé par l'admin, partagé par tous),
  // et non plus un réglage local par téléphone. Sert à la planification locale.
  static Future<bool> _cdEnabled() async =>
      (await GroupService.getCurrentGroup())?.notifCountdownEnabled ?? false;

  // ---------------------------------------------------------------------------
  // Alertes (moments) stockées localement
  // ---------------------------------------------------------------------------

  static List<AlertMoment> _readAlerts(SharedPreferences prefs) {
    final raw = prefs.getString(_alertsKey);
    if (raw == null) return [];
    try {
      final list = <AlertMoment>[];
      for (final e in jsonDecode(raw) as List) {
        final m = AlertMoment.fromJson(e);
        if (m != null) list.add(m);
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeAlerts(
      SharedPreferences prefs, List<AlertMoment> list) async {
    await prefs.setString(
        _alertsKey, jsonEncode(list.map((m) => m.toJson()).toList()));
  }

  static List<String> _readConsumed(SharedPreferences prefs) =>
      prefs.getStringList(_consumedAlertsKey) ?? const <String>[];

  /// Enregistre une alerte (dédoublonnée par id : si elle existe déjà, on
  /// garde l'entrée existante). Purge les alertes de plus de 24 h. Renvoie
  /// l'alerte stockée. Utilisable depuis l'isolat d'arrière-plan.
  static Future<AlertMoment> upsertAlert(AlertMoment m) async {
    final prefs = await SharedPreferences.getInstance();
    // Relit le disque : l'autre isolat (premier plan / arrière-plan) a pu
    // écrire entre-temps.
    await prefs.reload();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final list = _readAlerts(prefs)
        .where((e) => e.sentAtMs >= nowMs - _pruneAfterMs)
        .toList();
    final existing = list.where((e) => e.id == m.id);
    final AlertMoment stored;
    if (existing.isNotEmpty) {
      stored = existing.first;
    } else {
      stored = m;
      list.add(m);
    }
    await _writeAlerts(prefs, list);
    // Réveille le feed s'il est ouvert (sans effet dans l'isolat d'arrière-plan).
    momentTick.value++;
    return stored;
  }

  /// Alerte par id (null si inconnue).
  static Future<AlertMoment?> momentById(String id) async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final m in _readAlerts(prefs)) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Vrai si une photo a déjà été prise pour cette alerte.
  static Future<bool> isConsumed(String id) async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _readConsumed(prefs).contains(id);
  }

  /// Alerte en cours la plus récente : non consommée, non expirée, et du
  /// groupe ACTUEL. Ne consomme rien (bannière, bouton Capture).
  static Future<AlertMoment?> peekActiveAlert() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    // Relit le disque : l'alerte a pu être écrite par l'isolat d'arrière-plan
    // (push reçu app fermée) que l'app principale ne voit pas sinon.
    await prefs.reload();
    final group = await GroupService.getCurrentGroup();
    if (group == null) return null;
    final consumed = _readConsumed(prefs).toSet();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    AlertMoment? best;
    for (final m in _readAlerts(prefs)) {
      if (m.groupId != group.id) continue;
      if (consumed.contains(m.id)) continue;
      if (m.sentAtMs > nowMs + _clockSkewMs) continue; // pas encore commencé
      if (m.isExpired(nowMs)) continue;
      if (best == null || m.sentAtMs > best.sentAtMs) best = m;
    }
    return best;
  }

  /// Marque l'alerte comme consommée (photo prise ou tentée) : la bannière
  /// disparaît et on ne peut pas reprendre de photo pour cette alerte.
  static Future<void> consumeAlert(String id) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = [..._readConsumed(prefs)];
    if (!list.contains(id)) list.add(id);
    // Garde seulement les 100 plus récents pour ne pas grossir indéfiniment.
    final trimmed = list.length > 100 ? list.sublist(list.length - 100) : list;
    await prefs.setStringList(_consumedAlertsKey, trimmed);
    // Retire la notif de la barre (affichée par nous ou par Android/FCM, qui
    // utilise le tag = alertId).
    try {
      await _plugin.cancel(notifIdFor(id), tag: id);
      await _plugin.cancel(0, tag: id);
    } catch (_) {}
    momentTick.value++;
  }

  /// Efface toutes les alertes locales + l'ensemble « consommés ». À appeler
  /// au changement / départ de groupe pour ne pas garder les alertes de
  /// l'ancien groupe.
  static Future<void> clearMoments() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.remove(_alertsKey);
    await prefs.remove(_consumedAlertsKey);
    await prefs.remove(_legacyMomentsKey);
    await prefs.remove(_legacyConsumedSetKey);
    momentTick.value++;
  }

  /// Texte par défaut d'une alerte (même formulation que le serveur).
  static String defaultAlertBody(AlertMoment m) {
    final avec = m.names.trim().isEmpty ? '' : ' avec ${m.names}';
    return m.hasCountdown
        ? "C'est parti ! Tu as ${_fmtDuration(m.countdownSeconds)} pour prendre ta photo$avec."
        : "C'est le moment ! Prends ta photo$avec.";
  }

  /// Affiche la notif d'une alerte (push reçu app OUVERTE ; app fermée,
  /// c'est Android qui l'affiche à partir du bloc notification du push).
  static Future<void> showAlertNotification(
    AlertMoment m, {
    String? title,
    String? body,
  }) async {
    if (kIsWeb) return;
    final countdown = m.hasCountdown;
    final remainingMs = m.deadlineMs - DateTime.now().millisecondsSinceEpoch;
    await _plugin.show(
      notifIdFor(m.id),
      title ?? "📸 Snap'It",
      body ?? defaultAlertBody(m),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          tag: m.id,
          // Chrono natif qui décompte jusqu'à la deadline commune.
          usesChronometer: countdown,
          chronometerCountDown: countdown,
          when: countdown ? m.deadlineMs : null,
          showWhen: countdown,
          timeoutAfter: countdown && remainingMs > 0 ? remainingMs : null,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payloadFor(m.id),
    );
  }

  // ---------------------------------------------------------------------------
  // Planification locale (désactivée quand le serveur push est configuré)
  // ---------------------------------------------------------------------------

  /// Répartit [total] personnes en groupes d'AU PLUS [cap] (aussi égaux que
  /// possible, jamais de groupe géant ni de personne seule) et renvoie
  /// [début, fin) du groupe contenant l'index [idx]. Déterministe → identique
  /// sur tous les téléphones.
  static List<int> _groupBounds(int total, int idx, int cap) {
    if (cap < 2) cap = 2;
    var numGroups = (total + cap - 1) ~/ cap; // ceil(total / cap)
    // Chaque groupe doit avoir ≥ 2 personnes (≥ 1 nom) : on plafonne le nombre
    // de groupes pour éviter qu'une personne se retrouve seule.
    final maxGroups = total ~/ 2;
    if (maxGroups >= 1 && numGroups > maxGroups) numGroups = maxGroups;
    if (numGroups < 1) numGroups = 1;
    final base = total ~/ numGroups;
    final extra = total % numGroups; // les `extra` premiers groupes ont +1
    var acc = 0;
    for (var g = 0; g < numGroups; g++) {
      final gs = base + (g < extra ? 1 : 0);
      if (idx < acc + gs) return [acc, acc + gs];
      acc += gs;
    }
    return [0, total];
  }

  /// Cancels all pending notifications and schedules fresh random ones.
  static Future<void> scheduleRandom() async {
    if (kIsWeb) return;

    // On annule UNIQUEMENT les notifs planifiées (à venir), pas celles déjà
    // affichées dans la barre — sinon ouvrir l'app effacerait la notif push
    // qu'on vient de recevoir.
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      await _plugin.cancel(p.id);
    }

    // Le serveur (cron) envoie les alertes automatiques en temps réel, à tout
    // le monde en même temps. On ne planifie donc RIEN en local — sinon on
    // aurait des doublons ET l'effet « paquet de notifs » au réveil de l'app
    // (Android retient les alarmes locales quand l'app dort longtemps).
    if (AppConfig.pushEnabled) return;

    // Les notifications sont liées au groupe : sans groupe courant, on
    // n'en planifie aucune (corrige les notifs fantômes après un départ).
    final group = await GroupService.getCurrentGroup();
    if (group == null) return;

    final prefs = await SharedPreferences.getInstance();

    // Config partagée par tout le groupe (fixée par l'admin) → tous les
    // téléphones utilisent les mêmes réglages = notifs synchronisées.
    if (!group.notifEnabled) return;
    final timeLimitEnabled = group.notifTimeLimit;
    final startHour = timeLimitEnabled ? group.notifStartHour : 0;
    final endHour = timeLimitEnabled ? group.notifEndHour : 23;
    final minCount = group.notifMinCount;
    final maxCount = group.notifMaxCount;
    final minNames = group.notifMinNames;
    final maxNames = group.notifMaxNames;

    // Durée du compte à rebours de la notif (réglage « Compte à rebours » du
    // groupe) ; 2 min par défaut si la valeur est à 0.
    final countdownSeconds = group.notifCountdownSeconds;
    final durationSeconds = countdownSeconds > 0 ? countdownSeconds : 120;
    final countdownOn = group.notifCountdownEnabled;

    final now = DateTime.now();
    final selfUser = await GroupService.getCurrentUser();
    final selfEmail = selfUser?.email.trim().toLowerCase() ?? '';
    final selfUsername = selfUser?.username.trim().toLowerCase() ?? '';

    // Liste complète des membres, TRIÉE (identique sur tous les téléphones →
    // moments synchronisés sans serveur). Repli sur le cache si hors-ligne.
    List<GroupMember> members;
    try {
      members = await GroupService.getMembers(group.id);
    } catch (_) {
      members = [];
    }
    if (members.isEmpty) {
      final cached = await GroupService.getCachedMemberNames();
      // Repli hors-ligne : on donne à MON nom mon vrai email, sinon le test
      // « suis-je dans le moment ? » (basé sur l'email) ne matcherait jamais
      // et aucune notif ne serait planifiée. On ne relabellise que le PREMIER
      // nom qui correspond (au cas où deux membres auraient le même pseudo).
      var selfAssigned = false;
      members = cached.map((n) {
        final isSelf = !selfAssigned &&
            selfUsername.isNotEmpty &&
            n.trim().toLowerCase() == selfUsername;
        if (isSelf) selfAssigned = true;
        return GroupMember(
          username: n,
          email: isSelf ? selfEmail : n.trim().toLowerCase(),
          joinedAt: now,
        );
      }).toList();
    }
    // Prénoms ajoutés par l'admin : ajoutés comme « cibles » possibles (email
    // fictif « extra:… » qui ne correspond à personne → jamais notifiés eux-
    // mêmes, mais peuvent apparaître dans « prends une photo avec X »).
    // Dédoublonnage : on ignore un prénom en plus qui correspond déjà au pseudo
    // d'un membre (sinon la même personne apparaît deux fois).
    final memberNames =
        members.map((m) => m.username.trim().toLowerCase()).toSet();
    for (final n in group.extraNames) {
      final key = n.trim().toLowerCase();
      if (key.isEmpty || memberNames.contains(key)) continue;
      final e = 'extra:$key';
      if (members.any((m) => m.email == e)) continue;
      members.add(GroupMember(username: n.trim(), email: e, joinedAt: now));
      memberNames.add(key);
    }
    members.sort((a, b) => a.email.compareTo(b.email));
    if (members.length < 2) return; // il faut au moins 2 personnes

    int id = 0;
    // Alertes enregistrées localement : permettent, si on ouvre l'app sans
    // toucher la notif, de savoir qu'un moment photo est en cours.
    final moments = <AlertMoment>[];

    for (int day = 0; day < 7; day++) {
      final base = now.add(Duration(days: day));
      final totalMinutes = (endHour - startHour) * 60 + 59;
      if (totalMinutes <= 0) continue;

      // Numéro de jour absolu → graine commune à tous les appareils.
      final dayNum = DateTime(base.year, base.month, base.day)
              .millisecondsSinceEpoch ~/
          86400000;
      final dayRng = Random(_stableHash('${group.id}|$dayNum'));

      final range = (maxCount - minCount).abs();
      final dailyCount = minCount + (range == 0 ? 0 : dayRng.nextInt(range + 1));

      final offsets = List.generate(
        dailyCount,
        (_) => startHour * 60 + dayRng.nextInt(totalMinutes),
      )..sort();

      for (int i = 0; i < offsets.length; i++) {
        final offset = offsets[i];
        final scheduled = DateTime(
            base.year, base.month, base.day, offset ~/ 60, offset % 60);
        if (!scheduled.isAfter(now)) continue;

        // Partition SYNCHRONISÉE en petits groupes (identiques sur tous les
        // téléphones grâce à la graine commune). Chacun photographie les AUTRES
        // de son groupe → réciproque. Inclut les « prénoms en plus ». La taille
        // varie dans [min+1, max+1] mais respecte toujours le minimum, et
        // personne ne se retrouve sans nom.
        final mRng = Random(_stableHash('${group.id}|$dayNum|$i'));
        final total = members.length;
        // Taille max d'un groupe = nb de noms + 1 (moi inclus), dans [min+1,
        // max+1]. La répartition équilibrée garantit qu'AUCUN groupe ne dépasse
        // ce max (donc jamais « tout le monde ensemble »).
        final loS = (minNames + 1).clamp(2, total);
        final hiS = (maxNames + 1).clamp(loS, total);
        final cap = loS + mRng.nextInt(hiS - loS + 1);
        final ordered = [...members]..shuffle(mRng);
        final myIdx = ordered
            .indexWhere((m) => m.email.trim().toLowerCase() == selfEmail);
        if (myIdx < 0) continue;
        final b = _groupBounds(total, myIdx, cap);
        final targets = ordered
            .sublist(b[0], b[1])
            .where((m) => m.email.trim().toLowerCase() != selfEmail)
            .map((m) => m.username)
            .toList();
        if (targets.isEmpty) continue;
        final label = _joinNames(targets);
        final moment = AlertMoment(
          id: 'local_${group.id}_${scheduled.millisecondsSinceEpoch}',
          groupId: group.id,
          names: label,
          sentAtMs: scheduled.millisecondsSinceEpoch,
          countdownSeconds: countdownOn ? durationSeconds : 0,
        );
        moments.add(moment);
        await _schedule(id++, moment);
      }
    }

    await _writeAlerts(prefs, moments);
    debugPrint('NotificationService: scheduled $id notifications');
  }

  /// Hash stable et identique sur tous les appareils (pas String.hashCode).
  static int _stableHash(String s) {
    int h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static Future<void> _schedule(int id, AlertMoment m) async {
    final scheduledTime = DateTime.fromMillisecondsSinceEpoch(m.sentAtMs);
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // Le chrono qui descend + la disparition automatique ne s'appliquent QUE si
    // le compte à rebours est activé. Sinon la notif reste (pas de pression de
    // temps) pour qu'on ait le temps de prendre la photo.
    final countdownOn = m.hasCountdown && await _cdEnabled();

    await _plugin.zonedSchedule(
      id,
      '📸 ${m.names}',
      countdownOn
          ? 'Prends vite la photo — il te reste ${_fmtDuration(m.countdownSeconds)} !'
          : 'Prends ta photo avec ${m.names} !',
      tzTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Notifications pour capturer des moments spontanés',
          importance: Importance.max,
          priority: Priority.high,
          ticker: "Snap'It",
          category: AndroidNotificationCategory.reminder,
          // Chrono natif qui décompte jusqu'à la deadline (effet BeReal),
          // seulement si le compte à rebours est activé.
          usesChronometer: countdownOn,
          chronometerCountDown: countdownOn,
          when: countdownOn ? m.deadlineMs : null,
          showWhen: countdownOn,
          // La notif ne disparaît toute seule QUE si le compte à rebours est
          // activé ; sinon elle reste tant qu'on ne l'a pas ouverte.
          timeoutAfter: countdownOn ? m.countdownSeconds * 1000 : null,
          autoCancel: true,
          // Bouton interactif : ouvre directement la caméra
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              _captureActionId,
              '📸 Capturer maintenant',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: _iosCategoryId,
        ),
      ),
      payload: payloadFor(m.id),
      // Planification inexacte : ne nécessite aucune permission spéciale
      // (compatible Play Store) et reste fidèle à l'esprit « spontané ».
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Formate une durée en secondes : « 45 s », « 2 min », « 1 min 30 ».
  static String _fmtDuration(int seconds) {
    if (seconds < 60) return '$seconds s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '$m min' : '$m min $s';
  }

  /// Assemble une liste de prénoms : « A », « A et B », « A, B et C ».
  static String _joinNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} et ${names.last}';
  }
}
