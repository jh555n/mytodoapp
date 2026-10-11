import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
import '../domain/recurrence.dart';

class ScheduledReminder {
  const ScheduledReminder(this.todo, this.at);
  final Todo todo;
  final DateTime at;
}

class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool ready = false;
  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone));
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false),
    ));
    ready = true;
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  Future<void> rebuild(
      List<Todo> todos, Set<String> completed, RecurrenceEngine engine) async {
    if (!ready) return;
    final now = DateTime.now();
    final pending = <ScheduledReminder>[];
    for (final todo in todos) {
      if (todo.deleted ||
          todo.completed ||
          todo.reminderMinutes == null ||
          todo.readOnly) {
        continue;
      }
      final seed = todo.anchorAt ?? todo.startsAt;
      if (seed == null) continue;
      for (final occurrence in engine.between(
          todo,
          now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 60)))) {
        if (completed
            .contains('${todo.id}@${occurrence.anchor.toIso8601String()}')) {
          continue;
        }
        var at = occurrence.scheduled;
        if (todo.allDay) at = DateTime(at.year, at.month, at.day, 9);
        at = at.subtract(Duration(minutes: todo.reminderMinutes!));
        if (at.isAfter(now)) pending.add(ScheduledReminder(todo, at));
      }
    }
    pending.sort((a, b) => a.at.compareTo(b.at));
    // iOS permits a limited pending queue; reserve room and refresh on app resume.
    // Validate all dates before replacing the currently scheduled queue.
    await _plugin.cancelAll();
    var id = 1;
    for (final item in pending.take(48)) {
      await _plugin.zonedSchedule(
        id++,
        item.todo.title,
        item.todo.allDay ? '오늘의 할 일을 확인하세요' : '예정된 할 일이 있어요',
        tz.TZDateTime.from(item.at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails('todos', '할 일 알림',
              channelDescription: '예약된 Todo 알림',
              importance: Importance.high,
              priority: Priority.high,
              visibility: NotificationVisibility.private),
          iOS:
              DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: item.todo.id,
      );
    }
  }

  Future<void> cancelAll() async {
    if (ready) await _plugin.cancelAll();
  }
}

class NativePrivacy {
  static const _channel = MethodChannel('dev.dayweave/privacy');
  static Future<void> excludeFromBackup() =>
      _channel.invokeMethod<void>('excludeFromBackup');
}
