import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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
    final timeLimitEnabled = prefs.getBool('notif_time_limit_enabled') ?? true;
    final startHour = timeLimitEnabled ? (prefs.getInt('notif_start_hour') ?? 9) : 0;
    final endHour = timeLimitEnabled ? (prefs.getInt('notif_end_hour') ?? 21) : 23;
    final minCount = prefs.getInt('notif_min_count') ?? 2;
    final maxCount = prefs.getInt('notif_max_count') ?? 5;

    await _plugin.cancelAll();

    // Interrupteur global (réglage admin) : notifications désactivées.
    final notifsEnabled = prefs.getBool('notifs_enabled') ?? true;
    if (!notifsEnabled) return;

    // Les notifications sont liées au groupe : sans groupe courant, on
    // n'en planifie aucune (corrige les notifs fantômes après un départ).
    final group = await GroupService.getCurrentGroup();
    if (group == null) return;

    // Durée du compte à rebours de la notif = temps choisi pour prendre la
    // photo (paramètre « Compte à rebours »). Toujours cohérent avec la
    // caméra ; 2 min par défaut si la valeur est à 0.
    final countdownSeconds = prefs.getInt('countdown_seconds') ?? 15;
    final durationSeconds = countdownSeconds > 0 ? countdownSeconds : 120;

    // Prefer group member names, fall back to manually saved names
    List<String> names = await GroupService.getCachedMemberNames();
    if (names.isEmpty) names = await NamesService.getNames();
    if (names.isEmpty) return;

    final now = DateTime.now();
    final random = Random();
    int id = 0;

    // Schedule for the next 7 days
    for (int day = 0; day < 7; day++) {
      final base = now.add(Duration(days: day));
      final totalMinutes = (endHour - startHour) * 60 + 59;
      if (totalMinutes <= 0) continue;

      // Random count between min and max for this day
      final range = (maxCount - minCount).abs();
      final dailyCount = minCount + (range == 0 ? 0 : random.nextInt(range + 1));

      final minuteOffsets = List.generate(
        dailyCount,
        (_) => startHour * 60 + random.nextInt(totalMinutes),
      )..sort();

      for (final offset in minuteOffsets) {
        final scheduled = DateTime(
          base.year,
          base.month,
          base.day,
          offset ~/ 60,
          offset % 60,
        );
        if (scheduled.isAfter(now)) {
          final name = names[random.nextInt(names.length)];
          await _schedule(id++, scheduled, name, durationSeconds);
        }
      }
    }

    debugPrint('NotificationService: scheduled $id notifications');
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

  /// Envoie tout de suite une notification (sur cet appareil) avec un membre
  /// du groupe au hasard.
  static Future<void> sendImmediate() async {
    if (kIsWeb) return;
    List<String> names = await GroupService.getCachedMemberNames();
    if (names.isEmpty) names = await NamesService.getNames();
    if (names.isEmpty) return;
    final name = names[Random().nextInt(names.length)];
    await sendTestNotification(name);
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
