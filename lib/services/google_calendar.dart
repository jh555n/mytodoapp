import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../domain/models.dart';
import 'calendars.dart';

class GoogleCalendarConnector implements CalendarConnector {
  GoogleCalendarConnector({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;
  Map<String, dynamic> _eventColors = {};
  final GoogleSignIn _signIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
      'https://www.googleapis.com/auth/calendar.calendars.readonly',
      'https://www.googleapis.com/auth/calendar.events'
    ],
    clientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID').isEmpty
        ? null
        : const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID').isEmpty
        ? null
        : const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );
  @override
  CalendarProvider get provider => CalendarProvider.google;
  @override
  Future<CalendarAccount> connect() async {
    final user = await _signIn.signIn();
    if (user == null) throw const CalendarFailure('Google 연결을 취소했습니다.');
    return CalendarAccount(
        provider: provider, accountId: user.id, displayName: user.email);
  }

  @override
  Future<void> disconnect() async {
    await _signIn.disconnect();
  }

  Future<http.Response> _request(String method, String path,
      {Map<String, String>? query,
      Map<String, dynamic>? body,
      String? revision}) async {
    final user = _signIn.currentUser ?? await _signIn.signInSilently();
    if (user == null) {
      throw const CalendarFailure('Google 인증이 만료되었습니다. 다시 연결하세요.');
    }
    final headers = await user.authHeaders;
    final request = http.Request(
        method, Uri.https('www.googleapis.com', '/calendar/v3/$path', query));
    request.headers.addAll({
      ...headers,
      'Content-Type': 'application/json',
      if (revision != null) 'If-Match': revision
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
            await _client.send(request).timeout(const Duration(seconds: 20)))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 412) {
      throw const CalendarConflict(
          '외부에서 먼저 수정된 일정이 있습니다. 새로고침 후 변경 내용을 확인하세요.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CalendarFailure('Google 캘린더 접근 권한을 확인하거나 다시 연결하세요.');
    }
    if (method == 'DELETE' && response.statusCode == 404) return response;
    if (method == 'POST' && response.statusCode == 409) return response;
    if (response.statusCode >= 400) {
      throw CalendarFailure('Google 캘린더 요청 실패 (${response.statusCode})');
    }
    return response;
  }

  Future<List<Map<String, dynamic>>> _pages(
      String path, Map<String, String> query) async {
    final items = <Map<String, dynamic>>[];
    String? token;
    do {
      final response = await _request('GET', path,
          query: {...query, if (token != null) 'pageToken': token});
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      items.addAll((json['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)));
      token = json['nextPageToken'] as String?;
    } while (token != null);
    return items;
  }

  int _color(String? value) => value == null
      ? 0xFF6389C6
      : 0xFF000000 | int.parse(value.replaceFirst('#', ''), radix: 16);
  @override
  Future<List<RemoteCalendar>> calendars() async =>
      (await _pages('users/me/calendarList', {}))
          .map((c) => RemoteCalendar(
              id: c['id'] as String,
              name: (c['summaryOverride'] ?? c['summary'] ?? 'Google Calendar')
                  as String,
              color: _color(c['backgroundColor'] as String?),
              writable:
                  c['accessRole'] == 'owner' || c['accessRole'] == 'writer'))
          .toList();

  @override
  Future<List<TodoCategory>> categories(
      CalendarAccount account, List<RemoteCalendar> calendars) async {
    final result = <TodoCategory>[];
    if (calendars.isEmpty) return result;
    final colors = jsonDecode((await _request('GET', 'colors')).body)
        as Map<String, dynamic>;
    _eventColors = Map<String, dynamic>.from(colors['event'] as Map? ?? {});
    for (final calendar in calendars) {
      final key = calendarCategoryKey(account, calendar.id);
      result.add(TodoCategory(
          id: key,
          name: calendar.name,
          colorValue: calendar.color,
          remoteKey: key));
      for (final entry in _eventColors.entries) {
        final key = '${remotePrefix(account)}color:${calendar.id}:${entry.key}';
        result.add(TodoCategory(
            id: key,
            remoteKey: key,
            name: '${calendar.name} · 색상 ${entry.key}',
            colorValue: _color((entry.value as Map)['background'] as String?)));
      }
      final response = await _request(
          'GET', 'calendars/${Uri.encodeComponent(calendar.id)}');
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final labels =
          (json['labelProperties'] as Map?)?['eventLabels'] as List? ?? [];
      for (final raw in labels) {
        final label = raw as Map;
        final key =
            '${remotePrefix(account)}label:${calendar.id}:${label['id']}';
        result.add(TodoCategory(
            id: key,
            name: (label['name'] as String?) ?? calendar.name,
            colorValue: _color(label['backgroundColor'] as String?),
            remoteKey: key));
      }
    }
    return result;
  }

  Todo _decode(CalendarAccount account, RemoteCalendar calendar,
      Map<String, dynamic> e) {
    final start = e['start'] as Map;
    final allDay = start['date'] != null;
    final when = DateTime.parse((start['date'] ?? start['dateTime']) as String)
        .toLocal();
    final private = (e['extendedProperties'] as Map?)?['private'] as Map? ?? {};
    final managed = private['dayweave'] == '1';
    final id = eventKey(account, calendar.id, e['id'] as String);
    return Todo(
        id: managed && private['todoId'] is String
            ? private['todoId'] as String
            : id,
        title: e['summary'] as String? ?? '(제목 없음)',
        notes: e['description'] as String? ?? '',
        startsAt: when,
        anchorAt: when,
        allDay: allDay,
        categoryId: e['eventLabelId'] != null
            ? '${remotePrefix(account)}label:${calendar.id}:${e['eventLabelId']}'
            : e['colorId'] != null
                ? '${remotePrefix(account)}color:${calendar.id}:${e['colorId']}'
                : calendarCategoryKey(account, calendar.id),
        completed: managed && private['completed'] == 'true',
        createdAt:
            DateTime.tryParse(e['created'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(e['updated'] as String? ?? '') ?? DateTime.now(),
        provider: provider,
        calendarId: calendar.id,
        remoteKey: id,
        remoteRevision: e['etag'] as String?,
        readOnly: !managed || !calendar.writable);
  }

  @override
  Future<List<Todo>> events(CalendarAccount account, RemoteCalendar calendar,
      DateTime from, DateTime until) async {
    final data =
        await _pages('calendars/${Uri.encodeComponent(calendar.id)}/events', {
      'timeMin': from.toUtc().toIso8601String(),
      'timeMax': until.toUtc().toIso8601String(),
      'singleEvents': 'true',
      'maxResults': '2500',
      'eventLabelVersion': '1'
    });
    return data
        .where((e) => e['status'] != 'cancelled' && e['start'] != null)
        .map((e) => _decode(account, calendar, e))
        .toList();
  }

  @override
  Future<Todo> push(CalendarAccount account, Todo todo) async {
    if (todo.calendarId == null || todo.startsAt == null) {
      throw const CalendarFailure('캘린더에 보낼 할 일에는 날짜와 대상 캘린더가 필요합니다.');
    }
    if (todo.repeat.unit != RepeatUnit.none) {
      throw const CalendarFailure(
          '반복 할 일의 외부 전송은 예외 날짜 검증 전까지 지원하지 않습니다. 로컬로 저장하세요.');
    }
    final calendar = Uri.encodeComponent(todo.calendarId!);
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    final eventId = todo.remoteKey?.substring(prefix.length);
    Map<String, String> boundary(DateTime date) => todo.allDay
        ? {'date': dayKey(date)}
        : {'dateTime': date.toUtc().toIso8601String()};
    final start = todo.startsAt!;
    final end = todo.allDay
        ? DateTime(start.year, start.month, start.day + 1)
        : start.add(const Duration(minutes: 30));
    final labelPrefix = '${remotePrefix(account)}label:${todo.calendarId}:';
    final colorPrefix = '${remotePrefix(account)}color:${todo.calendarId}:';
    final body = <String, dynamic>{
      'summary': todo.title,
      'description': todo.notes,
      if (eventId == null) 'id': todo.id.replaceAll('-', '').toLowerCase(),
      'start': boundary(start),
      'end': boundary(end),
      'extendedProperties': {
        'private': {
          'dayweave': '1',
          'todoId': todo.id,
          'completed': todo.completed.toString()
        }
      },
      if (todo.categoryId?.startsWith(labelPrefix) ?? false)
        'eventLabelId': todo.categoryId!.substring(labelPrefix.length),
      if (todo.categoryId?.startsWith(colorPrefix) ?? false)
        'colorId': todo.categoryId!.substring(colorPrefix.length),
      'reminders': {'useDefault': false},
    };
    final response = await _request(eventId == null ? 'POST' : 'PATCH',
        'calendars/$calendar/events${eventId == null ? '' : '/${Uri.encodeComponent(eventId)}'}',
        body: body,
        revision: todo.remoteRevision,
        query: {'eventLabelVersion': '1'});
    final effectiveResponse = response.statusCode == 409
        ? await _request('GET', 'calendars/$calendar/events/${body['id']}')
        : response;
    final e = jsonDecode(effectiveResponse.body) as Map<String, dynamic>;
    if (response.statusCode == 409 &&
        ((e['extendedProperties'] as Map?)?['private'] as Map?)?['todoId'] !=
            todo.id) {
      throw const CalendarFailure('일정 ID 충돌이 발생했습니다. 다른 일정은 변경하지 않았습니다.');
    }
    if (response.statusCode == 409 &&
        (e['summary'] != body['summary'] ||
            (e['description'] ?? '') != body['description'] ||
            jsonEncode(e['start']) != jsonEncode(body['start']) ||
            ((e['extendedProperties'] as Map?)?['private']
                    as Map?)?['completed'] !=
                todo.completed.toString())) {
      throw const CalendarConflict('이미 저장된 일정과 기기 변경이 다릅니다. 유지할 변경을 선택하세요.');
    }
    return todo.change({
      'remoteKey': eventKey(account, todo.calendarId!, e['id'] as String),
      'remoteRevision': e['etag'],
      'dirty': false
    });
  }

  @override
  Future<void> delete(CalendarAccount account, Todo todo) async {
    if (todo.remoteKey == null || todo.calendarId == null || todo.readOnly) {
      return;
    }
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    final id = todo.remoteKey!.substring(prefix.length);
    await _request('DELETE',
        'calendars/${Uri.encodeComponent(todo.calendarId!)}/events/${Uri.encodeComponent(id)}',
        revision: todo.remoteRevision);
  }
}
