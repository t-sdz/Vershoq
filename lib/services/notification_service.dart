import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'names_service.dart';

// Must be top-level for the background isolate
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String personName)? _onTap;

  static const _channelId = 'vershoq_shots';
  static const _channelName = 'Photos spontanées';

  static Future<void> init({
    required void Function(String personName) onTap,
  }) async {
    _onTap = onTap;

    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      // Fallback to UTC if timezone detection fails
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
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
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  /// Cancels all pending notifications and schedules fresh random ones.
  static Future<void> scheduleRandom() async {
    final prefs = await SharedPreferences.getInstance();
    final startHour = prefs.getInt('notif_start_hour') ?? 9;
    final endHour = prefs.getInt('notif_end_hour') ?? 21;
    final dailyCount = prefs.getInt('notif_daily_count') ?? 3;

    await _plugin.cancelAll();

    final names = await NamesService.getNames();
    if (names.isEmpty) return;

    final now = DateTime.now();
    final random = Random();
    int id = 0;

    // Schedule for the next 7 days
    for (int day = 0; day < 7; day++) {
      final base = now.add(Duration(days: day));
      final totalMinutes = (endHour - startHour) * 60;
      if (totalMinutes <= 0) continue;

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
          await _schedule(id++, scheduled, name);
        }
      }
    }

    debugPrint('NotificationService: scheduled $id notifications');
  }

  static Future<void> _schedule(
    int id,
    DateTime scheduledTime,
    String personName,
  ) async {
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    await _plugin.zonedSchedule(
      id,
      '📸 C\'est l\'heure !',
      'Prends une photo de $personName maintenant !',
      tzTime,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'Notifications pour capturer des moments spontanés',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          ticker: 'Vershoq',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: personName,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
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
