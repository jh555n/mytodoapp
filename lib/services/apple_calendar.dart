import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'calendars.dart';

class AppleCalendarConnector implements CalendarConnector {
  static const _channel = MethodChannel('dev.dayweave/calendar');
  @override
  CalendarProvider get provider => CalendarProvider.apple;
  @override
  Future<CalendarAccount> connect() async {
    if (!Platform.isIOS) {
      throw const CalendarFailure('Apple 기기 캘린더는 iOS에서 연결할 수 있습니다.');
    }
    await _channel.invokeMethod<void>('requestAccess');
    return CalendarAccount(
        provider: provider, accountId: 'device', displayName: '기기에 등록된 캘린더');
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod<void>('disconnect');
  }

  @override
  Future<List<RemoteCalendar>> calendars() async {
    final data = await _channel.invokeListMethod<dynamic>('calendars') ?? [];
    return data.map((raw) {
      final c = Map<String, dynamic>.from(raw as Map);
      return RemoteCalendar(
          id: c['id'] as String,
          name: c['name'] as String,
          color: (c['color'] as num).toInt(),
          writable: c['writable'] as bool);
    }).toList();
  }

  @override
  Future<List<TodoCategory>> categories(
          CalendarAccount account, List<RemoteCalendar> calendars) async =>
      calendars.map((c) {
        final key = calendarCategoryKey(account, c.id);
        return TodoCategory(
            id: key, name: c.name, colorValue: c.color, remoteKey: key);
      }).toList();
  @override
  Future<List<Todo>> events(CalendarAccount account, RemoteCalendar calendar,
      DateTime from, DateTime until) async {
    final data = await _channel.invokeListMethod<dynamic>('events', {
          'calendarId': calendar.id,
          'from': from.millisecondsSinceEpoch,
          'until': until.millisecondsSinceEpoch
        }) ??
        [];
    return data.map((raw) {
      final e = Map<String, dynamic>.from(raw as Map);
      final at =
          DateTime.fromMillisecondsSinceEpoch((e['startsAt'] as num).toInt());
      final key = eventKey(account, calendar.id, e['id'] as String);
      return Todo(
          id: key,
          title: e['title'] as String,
          notes: e['notes'] as String? ?? '',
          startsAt: at,
          anchorAt: at,
          allDay: e['allDay'] as bool,
          createdAt: DateTime.now(),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
              (e['updatedAt'] as num).toInt()),
          categoryId: calendarCategoryKey(account, calendar.id),
          provider: provider,
          calendarId: calendar.id,
          remoteKey: key,
          remoteRevision: e['revision'] as String,
          completed: e['completed'] as bool,
          readOnly: !(e['managed'] as bool) || !calendar.writable);
    }).toList();
  }

  @override
  Future<Todo> push(CalendarAccount account, Todo todo) async {
    if (todo.startsAt == null ||
        todo.calendarId == null ||
        todo.repeat.unit != RepeatUnit.none) {
      throw const CalendarFailure('날짜가 있는 단일 할 일만 캘린더로 전송할 수 있습니다.');
    }
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    Map<String, dynamic> e;
    try {
      e = Map<String, dynamic>.from(await _channel.invokeMethod<Map>('save', {
            'id': todo.remoteKey?.substring(prefix.length),
            'calendarId': todo.calendarId,
            'title': todo.title,
            'notes': todo.notes,
            'allDay': todo.allDay,
            'startsAt': todo.startsAt!.millisecondsSinceEpoch,
            'completed': todo.completed,
            'revision': todo.remoteRevision,
          }) ??
          {});
    } on PlatformException catch (error) {
      if (error.message?.contains('외부에서 변경') ?? false) {
        throw CalendarConflict(error.message!);
      }
      rethrow;
    }
    return todo.change({
      'remoteKey': eventKey(account, todo.calendarId!, e['id'] as String),
      'remoteRevision': e['revision'],
      'dirty': false
    });
  }

  @override
  Future<void> delete(CalendarAccount account, Todo todo) async {
    if (todo.remoteKey == null || todo.readOnly) return;
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    try {
      await _channel.invokeMethod<void>('delete', {
        'id': todo.remoteKey!.substring(prefix.length),
        'revision': todo.remoteRevision
      });
    } on PlatformException catch (error) {
      if (error.message?.contains('외부에서 변경') ?? false) {
        throw CalendarConflict(error.message!);
      }
      rethrow;
    }
  }
}
