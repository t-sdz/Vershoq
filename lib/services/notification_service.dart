import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/group.dart';
import 'group_service.dart';
import 'names_service.dart';

// Must be top-level for the background isolate
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String personName)? _onTap;

  /// Incrémenté chaque fois qu'un moment est armé (push reçu app ouverte, ou
  /// envoi admin). Le feed l'écoute pour afficher la bannière immédiatement.
  static final ValueNotifier<int> momentTick = ValueNotifier<int>(0);

  static const _channelId = 'vershoq_shots';
  static const _channelName = 'Photos spontanées';
  static const _captureActionId = 'vershoq_capture';
  static const _iosCategoryId = 'vershoq_shot_category';
  static const _momentsKey = 'vershoq_moments';
  static const _consumedSetKey = 'vershoq_moments_consumed_set';

  /// Ensemble des moments déjà consommés (photo prise), par timestamp. On
  /// utilise un ENSEMBLE (pas un seul) pour gérer plusieurs alertes actives en
  /// même temps sans que l'une réapparaisse après avoir photographié l'autre.
  static Future<Set<int>> _getConsumed(SharedPreferences prefs) async {
    final raw = prefs.getStringList(_consumedSetKey);
    if (raw == null) return <int>{};
    return raw.map((s) => int.tryParse(s) ?? 0).toSet();
  }

  static Future<void> _addConsumed(SharedPreferences prefs, int t) async {
    final set = await _getConsumed(prefs);
    set.add(t);
    // Garde seulement les 50 plus récents pour ne pas grossir indéfiniment.
    final list = set.toList()..sort();
    final trimmed = list.length > 50 ? list.sublist(list.length - 50) : list;
    await prefs.setStringList(
        _consumedSetKey, trimmed.map((e) => e.toString()).toList());
  }

  static Future<void> init({
    required void Function(String personName) onTap,
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
        // Toutes nos notifs sont des « moments photo » : taper ouvre la caméra,
        // MÊME si le label (prénoms) est vide, sinon rien ne se passe.
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
      // Lancée en tapant une notif : on renvoie le label (éventuellement vide,
      // mais jamais null) pour que la caméra s'ouvre quand même.
      return details?.notificationResponse?.payload ?? '';
    }
    return null;
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  /// Durée pendant laquelle on peut encore prendre la photo après le début du
  /// moment. Sans compte à rebours (pas de pression), on laisse tout le temps
  /// (6 h). Avec compte à rebours, au moins 15 min pour ne pas rater le coche.
  // Compte à rebours : réglage du GROUPE (fixé par l'admin, partagé par tous),
  // et non plus un réglage local par téléphone.
  static Future<bool> _cdEnabled() async =>
      (await GroupService.getCurrentGroup())?.notifCountdownEnabled ?? false;
  static Future<int> _cdSeconds() async =>
      (await GroupService.getCurrentGroup())?.notifCountdownSeconds ?? 15;

  static Future<int> _momentWindowMs() async {
    final enabled = await _cdEnabled();
    final c = await _cdSeconds();
    if (enabled && c > 0) {
      return max(c * 1000, 15 * 60 * 1000);
    }
    return 6 * 60 * 60 * 1000;
  }

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

    // Planification LOCALE des alertes automatiques (chaque téléphone programme
    // ses notifs) : c'est la base qui marche de façon fiable, même sans serveur.
    // Le bouton admin « Envoyer une notif au groupe » reste, lui, simultané via
    // le push serveur.

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
    // Moments enregistrés localement : permettent, si on ouvre l'app sans
    // toucher la notif, de savoir qu'un moment photo est en cours.
    final moments = <Map<String, dynamic>>[];

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
        moments.add({
          't': scheduled.millisecondsSinceEpoch,
          'd': durationSeconds,
          'l': label,
        });
        await _schedule(id++, scheduled, label, durationSeconds);
      }
    }

    await prefs.setString(_momentsKey, jsonEncode(moments));
    debugPrint('NotificationService: scheduled $id notifications');
  }

  /// Renvoie le libellé du moment photo actuellement en cours (fenêtre du
  /// compte à rebours non expirée) s'il n'a pas déjà été consommé, sinon null.
  /// Sert à ouvrir directement la caméra quand on lance l'app.
  static Future<String?> activeMomentLabel() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    // Relit le disque : le moment a pu être écrit par l'isolat d'arrière-plan
    // (push reçu app fermée) que l'app principale ne voit pas sinon.
    await prefs.reload();
    final raw = prefs.getString(_momentsKey);
    if (raw == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final consumed = await _getConsumed(prefs);
    // Ouverture AUTOMATIQUE de la caméra au lancement : fenêtre COURTE (3 min),
    // pour ne se déclencher que si on ouvre l'app juste après un moment. Le
    // bandeau (peekActiveMoment), lui, reste disponible bien plus longtemps.
    const windowMs = 3 * 60 * 1000;
    try {
      // On prend le moment le plus récent encore actif.
      var bestT = 0;
      String? bestLabel;
      for (final e in jsonDecode(raw) as List) {
        final t = (e['t'] as num).toInt();
        if (nowMs >= t &&
            nowMs <= t + windowMs &&
            !consumed.contains(t) &&
            t > bestT) {
          bestT = t;
          bestLabel = e['l'] as String;
        }
      }
      if (bestLabel != null) {
        await _addConsumed(prefs, bestT);
        return bestLabel;
      }
    } catch (_) {}
    return null;
  }

  /// Calcule, pour CET appareil, les personnes à photographier (les autres
  /// membres de MON groupe, jamais moi). Basé sur le cache local (fonctionne
  /// aussi dans l'isolat d'arrière-plan).
  ///
  /// Si [seed] est fourni (graine commune envoyée par le serveur dans le
  /// push), TOUS les téléphones forment EXACTEMENT les mêmes groupes à partir
  /// de la liste triée pareil partout : l'appariement est donc réciproque
  /// (Tess voit « Max », Max voit « Tess »). Sans graine, tirage aléatoire.
  static Future<String?> buildMyMomentLabel({int? seed}) async {
    final group = await GroupService.getCurrentGroup();
    // Membres du groupe + prénoms ajoutés par l'admin (mêmes sur tous les
    // téléphones → réciprocité préservée).
    final cached = await GroupService.getCachedMemberNames();
    final all = <String>[...cached, ...?group?.extraNames];
    final self =
        (await GroupService.getCurrentUser())?.username.trim().toLowerCase();

    if (seed == null) {
      // Ancien comportement (pas de graine) : tirage local aléatoire.
      final rng = Random();
      var names = all;
      if (self != null && self.isNotEmpty) {
        names = names.where((n) => n.trim().toLowerCase() != self).toList();
      }
      if (names.isEmpty) return null;
      final shuffled = [...names]..shuffle(rng);
      final lo = (group?.notifMinNames ?? 1).clamp(1, shuffled.length);
      final hi = (group?.notifMaxNames ?? 3).clamp(lo, shuffled.length);
      final count = lo + rng.nextInt(hi - lo + 1);
      return _joinNames(shuffled.take(count).toList());
    }

    // Partition SYNCHRONISÉE basée sur l'IDENTITÉ (email), pas le pseudo :
    // - « moi » est exclu par EMAIL → je ne me vois jamais, même si mon pseudo
    //   dans le groupe diffère de mon pseudo de profil ;
    // - les « prénoms en plus » qui correspondent déjà à un membre sont ignorés
    //   (évite qu'une même personne apparaisse deux fois).
    final selfEmail =
        (await GroupService.getCurrentUser())?.email.trim().toLowerCase() ?? '';

    // Liste AUTORITAIRE des membres (email + pseudo) depuis Firestore → même
    // liste sur tous les téléphones. Repli sur le cache si indisponible.
    final now = DateTime.now();
    List<GroupMember> pool;
    try {
      pool = group != null ? await GroupService.getMembers(group.id) : [];
    } catch (_) {
      pool = [];
    }
    if (pool.isEmpty) {
      pool = cached
          .map((n) => GroupMember(
              username: n, email: n.trim().toLowerCase(), joinedAt: now))
          .toList();
    }
    // Prénoms en plus, dédoublonnés contre les pseudos de membres.
    final seen = pool.map((m) => m.username.trim().toLowerCase()).toSet();
    for (final n in (group?.extraNames ?? const <String>[])) {
      final key = n.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      pool.add(GroupMember(username: n.trim(), email: 'extra:$key', joinedAt: now));
      seen.add(key);
    }
    // Je dois être dans la liste pour être réparti ; sinon je m'ajoute.
    if (selfEmail.isNotEmpty &&
        !pool.any((m) => m.email.trim().toLowerCase() == selfEmail)) {
      final me = await GroupService.getCurrentUser();
      if (me != null) pool.add(me);
    }
    if (pool.length < 2 || selfEmail.isEmpty) return null;

    // Tri stable par email (unique) → ordre identique sur tous les téléphones.
    pool.sort((a, b) =>
        a.email.trim().toLowerCase().compareTo(b.email.trim().toLowerCase()));

    final rng = Random(seed);
    final total = pool.length;
    final loS = ((group?.notifMinNames ?? 1) + 1).clamp(2, total);
    final hiS = ((group?.notifMaxNames ?? 3) + 1).clamp(loS, total);
    final cap = loS + rng.nextInt(hiS - loS + 1);
    final ordered = [...pool]..shuffle(rng);
    final idx =
        ordered.indexWhere((m) => m.email.trim().toLowerCase() == selfEmail);
    if (idx < 0) return null;
    final b = _groupBounds(total, idx, cap);
    final others = ordered
        .sublist(b[0], b[1])
        .where((m) => m.email.trim().toLowerCase() != selfEmail)
        .map((m) => m.username)
        .toList();
    if (others.isEmpty) return null;
    return _joinNames(others);
  }

  /// Enregistre un moment reçu par push (FCM) → bannière + caméra.
  /// Le libellé peut être vide (le téléphone n'a pas encore le cache des
  /// prénoms) : on arme quand même le moment pour que la bannière apparaisse.
  static Future<void> registerRemoteMoment(String label) async {
    final c = await _cdSeconds();
    await _addMoment(label, c > 0 ? c : 120);
    // Réveille le feed s'il est ouvert (isolat principal uniquement).
    momentTick.value++;
  }

  /// Affiche une notification (utilisé quand un push arrive app ouverte).
  static Future<void> showRemote(
      String title, String body, String label) async {
    if (kIsWeb) return;
    await _plugin.show(
      9998,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: label,
    );
  }

  /// Comme activeMomentLabel mais SANS consommer (pour afficher une bannière).
  static Future<String?> peekActiveMoment() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    // Relit le disque : le moment a pu être écrit par l'isolat d'arrière-plan
    // (push reçu app fermée) que l'app principale ne voit pas sinon.
    await prefs.reload();
    final raw = prefs.getString(_momentsKey);
    if (raw == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowMs = await _momentWindowMs();
    final consumed = await _getConsumed(prefs);
    var bestT = 0;
    String? best;
    try {
      for (final e in jsonDecode(raw) as List) {
        final t = (e['t'] as num).toInt();
        // On ignore un moment déjà consommé (photo déjà prise) : le bandeau
        // disparaît alors et on ne peut pas reprendre une 2e photo pour la
        // même alerte.
        if (nowMs >= t &&
            nowMs <= t + windowMs &&
            !consumed.contains(t) &&
            t > bestT) {
          bestT = t;
          best = e['l'] as String;
        }
      }
    } catch (_) {}
    return best;
  }

  /// Marque le moment actuellement affiché (le plus récent NON consommé) comme
  /// « consommé » (photo prise), pour que le bandeau disparaisse et qu'on ne
  /// puisse pas reprendre une photo pour la même alerte (notif ou bandeau).
  /// On choisit le même moment que peekActiveMoment afin de consommer bien
  /// celui que l'utilisateur voyait, même s'il y a plusieurs alertes actives.
  static Future<void> consumeActiveMoment() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_momentsKey);
    if (raw == null) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowMs = await _momentWindowMs();
    final consumed = await _getConsumed(prefs);
    var bestT = 0;
    try {
      for (final e in jsonDecode(raw) as List) {
        final t = (e['t'] as num).toInt();
        if (nowMs >= t &&
            nowMs <= t + windowMs &&
            !consumed.contains(t) &&
            t > bestT) {
          bestT = t;
        }
      }
    } catch (_) {}
    if (bestT > 0) await _addConsumed(prefs, bestT);
  }

  /// Enregistre un moment « maintenant » (utilisé par l'envoi immédiat) pour
  /// que la caméra/bannière s'active tout de suite.
  static Future<void> _addMoment(String label, int durationSeconds) async {
    final prefs = await SharedPreferences.getInstance();
    final list = <dynamic>[];
    final raw = prefs.getString(_momentsKey);
    if (raw != null) {
      try {
        list.addAll(jsonDecode(raw) as List);
      } catch (_) {}
    }
    list.add({
      't': DateTime.now().millisecondsSinceEpoch,
      'd': durationSeconds,
      'l': label,
    });
    await prefs.setString(_momentsKey, jsonEncode(list));
  }

  /// Hash stable et identique sur tous les appareils (pas String.hashCode).
  static int _stableHash(String s) {
    int h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static Future<void> _schedule(
    int id,
    DateTime scheduledTime,
    String personName,
    int durationSeconds,
  ) async {
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    // Le chrono qui descend + la disparition automatique ne s'appliquent QUE si
    // le compte à rebours est activé. Sinon la notif reste (pas de pression de
    // temps) pour qu'on ait le temps de prendre la photo.
    final countdownOn = await _cdEnabled();
    final deadline = scheduledTime.add(Duration(seconds: durationSeconds));

    await _plugin.zonedSchedule(
      id,
      '📸 $personName',
      countdownOn
          ? 'Prends vite la photo — il te reste ${_fmtDuration(durationSeconds)} !'
          : 'Prends ta photo avec $personName !',
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
          when: countdownOn ? deadline.millisecondsSinceEpoch : null,
          showWhen: countdownOn,
          // La notif ne disparaît toute seule QUE si le compte à rebours est
          // activé ; sinon elle reste tant qu'on ne l'a pas ouverte.
          timeoutAfter: countdownOn ? durationSeconds * 1000 : null,
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
      payload: personName,
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

  /// Envoie tout de suite une notification (sur cet appareil) avec 1 à 3
  /// membres du groupe au hasard (jamais soi-même).
  static Future<void> sendImmediate() async {
    if (kIsWeb) return;
    final random = Random();
    final group = await GroupService.getCurrentGroup();
    List<String> names = [
      ...await GroupService.getCachedMemberNames(),
      ...?group?.extraNames,
    ];
    if (names.isEmpty) names = await NamesService.getNames();
    final self = (await GroupService.getCurrentUser())?.username.trim().toLowerCase();
    if (self != null && self.isNotEmpty) {
      names = names.where((n) => n.trim().toLowerCase() != self).toList();
    }
    if (names.isEmpty) return;
    final shuffled = [...names]..shuffle(random);

    // Respecte le réglage min/max noms du groupe, borné par la taille.
    final maxTargets = shuffled.length;
    final lo = (group?.notifMinNames ?? 1).clamp(1, maxTargets);
    final hi = (group?.notifMaxNames ?? 3).clamp(lo, maxTargets);
    final count = lo + random.nextInt(hi - lo + 1);
    final label = _joinNames(shuffled.take(count).toList());
    final countdownSeconds = group?.notifCountdownSeconds ?? 15;
    // Enregistre le moment → l'app ouvrira la caméra / affichera la bannière.
    await _addMoment(label, countdownSeconds > 0 ? countdownSeconds : 120);
    await sendTestNotification(label);
  }

  /// Sends an immediate test notification with a random name.
  static Future<void> sendTestNotification(String personName) async {
    await _plugin.show(
      9999,
      '📸 C\'est l\'heure !',
      'Prends une photo de $personName maintenant !',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: personName,
    );
  }
}
