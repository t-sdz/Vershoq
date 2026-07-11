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

  static const _channelId = 'vershoq_shots';
  static const _channelName = 'Photos spontanées';
  static const _captureActionId = 'vershoq_capture';
  static const _iosCategoryId = 'vershoq_shot_category';
  static const _momentsKey = 'vershoq_moments';
  static const _consumedKey = 'vershoq_moment_consumed';

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
        if (response.payload != null && response.payload!.isNotEmpty) {
          _onTap?.call(response.payload!);
        }
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
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }

  /// Cancels all pending notifications and schedules fresh random ones.
  static Future<void> scheduleRandom() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();

    await _plugin.cancelAll();

    // Les notifications sont liées au groupe : sans groupe courant, on
    // n'en planifie aucune (corrige les notifs fantômes après un départ).
    final group = await GroupService.getCurrentGroup();
    if (group == null) return;

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

    // Durée du compte à rebours de la notif (paramètre local « Compte à
    // rebours ») ; 2 min par défaut si la valeur est à 0.
    final countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
    final durationSeconds = countdownSeconds > 0 ? countdownSeconds : 120;

    final now = DateTime.now();
    final selfEmail =
        (await GroupService.getCurrentUser())?.email.trim().toLowerCase() ?? '';

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
      members = cached
          .map((n) => GroupMember(
              username: n, email: n.trim().toLowerCase(), joinedAt: now))
          .toList();
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

        // Moment synchronisé : même sous-groupe tiré sur tous les téléphones.
        final mRng = Random(_stableHash('${group.id}|$dayNum|$i'));
        final pool = [...members]..shuffle(mRng);
        // Nombre de noms (personnes à photographier) borné par l'admin, puis
        // par la taille du groupe. Le sous-groupe = noms + 1 (soi inclus).
        final maxTargets = members.length - 1;
        final lo = minNames.clamp(1, maxTargets);
        final hi = maxNames.clamp(lo, maxTargets);
        final namesCount = lo + mRng.nextInt(hi - lo + 1);
        final subset = pool.take(namesCount + 1).toList();

        // Je ne suis notifié que si je fais partie du moment.
        final inMoment =
            subset.any((m) => m.email.trim().toLowerCase() == selfEmail);
        if (!inMoment) continue;

        // Les personnes à photographier = les autres du sous-groupe.
        final targets = subset
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
    final raw = prefs.getString(_momentsKey);
    if (raw == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final consumed = prefs.getInt(_consumedKey) ?? 0;
    try {
      // Fenêtre pour ouvrir l'app et prendre la photo : au moins 5 min
      // (indépendante du court compte à rebours affiché dans la notif).
      const windowMs = 5 * 60 * 1000;
      // On prend le moment le plus récent encore actif.
      var bestT = 0;
      String? bestLabel;
      for (final e in jsonDecode(raw) as List) {
        final t = (e['t'] as num).toInt();
        if (nowMs >= t && nowMs <= t + windowMs && t != consumed && t > bestT) {
          bestT = t;
          bestLabel = e['l'] as String;
        }
      }
      if (bestLabel != null) {
        await prefs.setInt(_consumedKey, bestT);
        return bestLabel;
      }
    } catch (_) {}
    return null;
  }

  /// Calcule, pour CET appareil, les personnes à photographier (les autres
  /// membres, jamais soi), en respectant le min/max noms du groupe. Basé sur
  /// le cache local (fonctionne aussi dans l'isolat d'arrière-plan).
  static Future<String?> buildMyMomentLabel() async {
    final rng = Random();
    List<String> names = await GroupService.getCachedMemberNames();
    final self =
        (await GroupService.getCurrentUser())?.username.trim().toLowerCase();
    if (self != null && self.isNotEmpty) {
      names = names.where((n) => n.trim().toLowerCase() != self).toList();
    }
    if (names.isEmpty) return null;
    final group = await GroupService.getCurrentGroup();
    final shuffled = [...names]..shuffle(rng);
    final lo = (group?.notifMinNames ?? 1).clamp(1, shuffled.length);
    final hi = (group?.notifMaxNames ?? 3).clamp(lo, shuffled.length);
    final count = lo + rng.nextInt(hi - lo + 1);
    return _joinNames(shuffled.take(count).toList());
  }

  /// Enregistre un moment reçu par push (FCM) → bannière + caméra.
  /// Le libellé peut être vide (le téléphone n'a pas encore le cache des
  /// prénoms) : on arme quand même le moment pour que la bannière apparaisse.
  static Future<void> registerRemoteMoment(String label) async {
    final prefs = await SharedPreferences.getInstance();
    final c = prefs.getInt('countdown_seconds') ?? 15;
    await _addMoment(label, c > 0 ? c : 120);
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
    final raw = prefs.getString(_momentsKey);
    if (raw == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const windowMs = 5 * 60 * 1000;
    var bestT = 0;
    String? best;
    try {
      for (final e in jsonDecode(raw) as List) {
        final t = (e['t'] as num).toInt();
        if (nowMs >= t && nowMs <= t + windowMs && t > bestT) {
          bestT = t;
          best = e['l'] as String;
        }
      }
    } catch (_) {}
    return best;
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

    // Compte à rebours façon BeReal : la notif affiche un chrono qui descend
    // depuis la durée choisie, rendu nativement par Android. Le titre montre
    // le prénom et le chrono natif affiche le temps à côté (« nom - time »).
    final deadline = scheduledTime.add(Duration(seconds: durationSeconds));

    await _plugin.zonedSchedule(
      id,
      '📸 $personName',
      'Prends vite la photo — il te reste ${_fmtDuration(durationSeconds)} !',
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
          // Chrono natif qui décompte jusqu'à la deadline (effet BeReal)
          usesChronometer: true,
          chronometerCountDown: true,
          when: deadline.millisecondsSinceEpoch,
          showWhen: true,
          // La notif disparaît toute seule à la fin du compte à rebours
          // (si l'utilisateur la loupe, elle ne reste pas indéfiniment).
          timeoutAfter: durationSeconds * 1000,
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
    List<String> names = await GroupService.getCachedMemberNames();
    if (names.isEmpty) names = await NamesService.getNames();
    final self = (await GroupService.getCurrentUser())?.username.trim().toLowerCase();
    if (self != null && self.isNotEmpty) {
      names = names.where((n) => n.trim().toLowerCase() != self).toList();
    }
    if (names.isEmpty) return;
    final shuffled = [...names]..shuffle(random);

    // Respecte le réglage min/max noms du groupe, borné par la taille.
    final group = await GroupService.getCurrentGroup();
    final maxTargets = shuffled.length;
    final lo = (group?.notifMinNames ?? 1).clamp(1, maxTargets);
    final hi = (group?.notifMaxNames ?? 3).clamp(lo, maxTargets);
    final count = lo + random.nextInt(hi - lo + 1);
    final label = _joinNames(shuffled.take(count).toList());
    final prefs = await SharedPreferences.getInstance();
    final countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
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
