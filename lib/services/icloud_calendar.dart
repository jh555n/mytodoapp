import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:timezone/timezone.dart' as tz;
import '../domain/models.dart';
import 'calendars.dart';

// CalDAV adapter: device-held app-specific password, HTTPS only, no backend.
// Must be tested against an actual iCloud account before release.
class ICloudCalendarConnector implements CalendarConnector {
  ICloudCalendarConnector({this.email, this.password, http.Client? client})
      : _client = client ?? http.Client();
  String? email;
  String? password;
  final http.Client _client;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
      iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device));
  Uri? _home;
  @override
  CalendarProvider get provider => CalendarProvider.icloud;

  Uri _trusted(Uri uri) {
    if (uri.scheme != 'https' ||
        !(uri.host == 'icloud.com' || uri.host.endsWith('.icloud.com')) ||
        (uri.hasPort && uri.port != 443) ||
        uri.userInfo.isNotEmpty) {
      throw const CalendarFailure('iCloud가 아닌 주소로 인증 정보를 보낼 수 없습니다.');
    }
    return uri;
  }

  Future<http.Response> _request(String method, Uri uri,
      {String? body, String depth = '0', String? revision}) async {
    email ??= await _secure.read(key: 'icloud.email');
    password ??= await _secure.read(key: 'icloud.password');
    if (email == null || password == null) {
      throw const CalendarFailure('iCloud 연결 정보가 없습니다.');
    }
    final request = http.Request(method, _trusted(uri));
    // Don't forward credentials through redirects, even to another iCloud host.
    request.followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Basic ${base64Encode(utf8.encode('$email:$password'))}',
      'Depth': depth,
      'Content-Type': method == 'PUT'
          ? 'text/calendar; charset=utf-8'
          : 'application/xml; charset=utf-8',
      if (revision != null) 'If-Match': revision,
      if (method == 'PUT' && revision == null) 'If-None-Match': '*'
    });
    if (body != null) request.body = body;
    final response = await http.Response.fromStream(
            await _client.send(request).timeout(const Duration(seconds: 20)))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 412) {
      throw const CalendarConflict('외부에서 수정된 iCloud 일정입니다. 먼저 새로고침하세요.');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CalendarFailure('Apple ID와 앱 전용 암호, iCloud 캘린더 활성화를 확인하세요.');
    }
    if (response.statusCode >= 300 &&
        !(method == 'DELETE' && response.statusCode == 404)) {
      throw CalendarFailure('iCloud 요청 실패 (${response.statusCode})');
    }
    return response;
  }

  String? _text(XmlNode node, String name) {
    final elements = node.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == name);
    return elements.isEmpty ? null : elements.first.innerText;
  }

  @override
  Future<CalendarAccount> connect() async {
    final root = Uri.parse('https://caldav.icloud.com/');
    final principalResponse = await _request('PROPFIND', root,
        body:
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>');
    final principalXml = XmlDocument.parse(principalResponse.body);
    final principalNodes = principalXml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'current-user-principal');
    if (principalNodes.isEmpty) {
      throw const CalendarFailure('iCloud 계정 경로를 찾지 못했습니다.');
    }
    final href = _text(principalNodes.first, 'href');
    if (href == null) throw const CalendarFailure('iCloud 계정 주소가 없습니다.');
    final principal = _trusted(root.resolve(href));
    final homeResponse = await _request('PROPFIND', principal,
        body:
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>');
    final homeXml = XmlDocument.parse(homeResponse.body);
    final homeNodes = homeXml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'calendar-home-set');
    if (homeNodes.isEmpty || _text(homeNodes.first, 'href') == null) {
      throw const CalendarFailure('iCloud 캘린더 경로를 찾지 못했습니다.');
    }
    _home = _trusted(principal.resolve(_text(homeNodes.first, 'href')!));
    await _secure.write(key: 'icloud.email', value: email);
    await _secure.write(key: 'icloud.password', value: password);
    return CalendarAccount(
        provider: provider,
        accountId: email!.toLowerCase(),
        displayName: email!);
  }

  @override
  Future<void> disconnect() async {
    await _secure.delete(key: 'icloud.email');
    await _secure.delete(key: 'icloud.password');
    email = null;
    password = null;
    _home = null;
  }

  @override
  Future<List<RemoteCalendar>> calendars() async {
    if (_home == null) await connect();
    final response = await _request('PROPFIND', _home!,
        depth: '1',
        body:
            '<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:a="http://apple.com/ns/ical/" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:displayname/><d:resourcetype/><a:calendar-color/><d:current-user-privilege-set/></d:prop></d:propfind>');
    final xml = XmlDocument.parse(response.body);
    final result = <RemoteCalendar>[];
    for (final entry in xml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'response')) {
      if (!entry.descendants
          .whereType<XmlElement>()
          .any((e) => e.name.local == 'calendar')) {
        continue;
      }
      final href = _text(entry, 'href');
      if (href == null) continue;
      final color =
          (_text(entry, 'calendar-color') ?? '#6389C6').replaceFirst('#', '');
      final rgb = color.length >= 6
          ? int.tryParse(color.substring(0, 6), radix: 16)
          : null;
      result.add(RemoteCalendar(
          id: _trusted(_home!.resolve(href)).toString(),
          name: _text(entry, 'displayname') ?? 'iCloud Calendar',
          color: 0xFF000000 | (rgb ?? 0x6389C6),
          writable: entry.descendants
              .whereType<XmlElement>()
              .any((e) => e.name.local == 'write')));
    }
    return result;
  }

  @override
  Future<List<TodoCategory>> categories(
          CalendarAccount account, List<RemoteCalendar> calendars) async =>
      calendars
          .map((c) => TodoCategory(
              id: calendarCategoryKey(account, c.id),
              remoteKey: calendarCategoryKey(account, c.id),
              name: c.name,
              colorValue: c.color))
          .toList();

  String _icalDate(DateTime at) =>
      '${at.toUtc().toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}Z';
  @override
  Future<List<Todo>> events(CalendarAccount account, RemoteCalendar calendar,
      DateTime from, DateTime until) async {
    final response = await _request('REPORT', Uri.parse(calendar.id),
        depth: '1',
        body:
            '<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:getetag/><c:calendar-data><c:expand start="${_icalDate(from)}" end="${_icalDate(until)}"/></c:calendar-data></d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="${_icalDate(from)}" end="${_icalDate(until)}"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>');
    final xml = XmlDocument.parse(response.body);
    final result = <Todo>[];
    for (final entry in xml.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'response')) {
      final data = _text(entry, 'calendar-data');
      final href = _text(entry, 'href');
      if (data == null || href == null) continue;
      final resource =
          _trusted(Uri.parse(calendar.id).resolve(href)).toString();
      for (final event in ICalendarCodec.parse(data)) {
        final at = event['startsAt'] as DateTime;
        final key = eventKey(
            account, calendar.id, '$resource#${event['recurrenceId'] ?? ''}');
        final uid = event['uid'] as String?;
        final localId = (event['managed'] as bool) &&
                uid != null &&
                uid.endsWith('@dayweave') &&
                event['recurrenceId'] == null
            ? uid.substring(0, uid.length - '@dayweave'.length)
            : key;
        result.add(Todo(
            id: localId,
            remoteKey: key,
            remoteRevision: _text(entry, 'getetag'),
            title: event['title'] as String,
            notes: event['notes'] as String,
            startsAt: at,
            anchorAt: at,
            allDay: event['allDay'] as bool,
            createdAt: at,
            updatedAt: at,
            provider: provider,
            calendarId: calendar.id,
            categoryId: calendarCategoryKey(account, calendar.id),
            completed: event['completed'] as bool,
            readOnly: !(event['managed'] as bool) ||
                !calendar.writable ||
                event['recurrenceId'] != null));
      }
    }
    return result;
  }

  @override
  Future<Todo> push(CalendarAccount account, Todo todo) async {
    if (todo.startsAt == null ||
        todo.calendarId == null ||
        todo.repeat.unit != RepeatUnit.none) {
      throw const CalendarFailure('iCloud 전송에는 날짜가 있는 단일 할 일이 필요합니다.');
    }
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    final resource = todo.remoteKey == null
        ? Uri.parse(todo.calendarId!)
            .resolve('${Uri.encodeComponent(todo.id)}.ics')
        : Uri.parse(todo.remoteKey!.substring(prefix.length).split('#').first);
    final response = await _request('PUT', resource,
        revision: todo.remoteRevision, body: ICalendarCodec.encode(todo));
    final revision = response.headers['etag'];
    if (revision == null) {
      throw const CalendarFailure('저장은 되었지만 변경 버전을 확인할 수 없습니다. 먼저 새로고침하세요.');
    }
    return todo.change({
      'remoteKey': eventKey(account, todo.calendarId!, '$resource#'),
      'remoteRevision': revision,
      'dirty': false
    });
  }

  @override
  Future<void> delete(CalendarAccount account, Todo todo) async {
    if (todo.remoteKey == null || todo.readOnly) return;
    final prefix = '${remotePrefix(account)}event:${todo.calendarId}:';
    await _request('DELETE',
        Uri.parse(todo.remoteKey!.substring(prefix.length).split('#').first),
        revision: todo.remoteRevision);
  }
}

class ICalendarCodec {
  static String _unescape(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (value[i] == '\\' && i + 1 < value.length) {
        final next = value[++i];
        out.write(next == 'n' || next == 'N' ? '\n' : next);
      } else {
        out.write(value[i]);
      }
    }
    return out.toString();
  }

  static String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('\r\n', '\n')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;')
      .replaceAll('\r', '');
  static List<Map<String, dynamic>> parse(String data) {
    final lines =
        data.replaceAll(RegExp(r'\r?\n[ \t]'), '').split(RegExp(r'\r?\n'));
    final events = <Map<String, dynamic>>[];
    Map<String, String>? fields;
    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        fields = {};
        continue;
      }
      if (line == 'END:VEVENT' && fields != null) {
        final startEntry =
            fields.entries.where((e) => e.key.split(';').first == 'DTSTART');
        if (startEntry.isNotEmpty && fields['STATUS'] != 'CANCELLED') {
          final start = startEntry.first;
          final raw = start.value;
          final allDay = raw.length == 8;
          DateTime at = DateTime.parse(allDay
              ? '${raw.substring(0, 4)}-${raw.substring(4, 6)}-${raw.substring(6, 8)}'
              : raw);
          final tzid = RegExp(r'TZID=([^;]+)').firstMatch(start.key)?.group(1);
          if (tzid != null && !raw.endsWith('Z')) {
            at = tz.TZDateTime(tz.getLocation(tzid), at.year, at.month, at.day,
                    at.hour, at.minute)
                .toLocal();
          } else {
            at = at.toLocal();
          }
          final recurrence = fields.entries
              .where((e) => e.key.split(';').first == 'RECURRENCE-ID');
          events.add({
            'startsAt': at,
            'allDay': allDay,
            'title': _unescape(fields['SUMMARY'] ?? '(제목 없음)'),
            'uid': _unescape(fields['UID'] ?? ''),
            'notes': _unescape(fields['DESCRIPTION'] ?? ''),
            'managed': fields['X-DAYWEAVE'] == '1',
            'completed': fields['X-DAYWEAVE-COMPLETED'] == 'TRUE',
            'recurrenceId': recurrence.isEmpty ? null : recurrence.first.value
          });
        }
        fields = null;
        continue;
      }
      if (fields != null && line.contains(':')) {
        final index = line.indexOf(':');
        fields[line.substring(0, index)] = line.substring(index + 1);
      }
    }
    return events;
  }

  static String encode(Todo todo) {
    final start = todo.startsAt!;
    String date(DateTime at) =>
        '${at.toUtc().toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}Z';
    final end = todo.allDay
        ? DateTime(start.year, start.month, start.day + 1)
        : start.add(const Duration(minutes: 30));
    final lines = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Dayweave//Todo//KO',
      'BEGIN:VEVENT',
      'UID:${_escape(todo.id)}@dayweave',
      'DTSTAMP:${date(DateTime.now())}',
      if (todo.allDay)
        'DTSTART;VALUE=DATE:${dayKey(start).replaceAll('-', '')}'
      else
        'DTSTART:${date(start)}',
      if (todo.allDay)
        'DTEND;VALUE=DATE:${dayKey(end).replaceAll('-', '')}'
      else
        'DTEND:${date(end)}',
      'SUMMARY:${_escape(todo.title)}',
      'DESCRIPTION:${_escape(todo.notes)}',
      'X-DAYWEAVE:1',
      'X-DAYWEAVE-COMPLETED:${todo.completed ? 'TRUE' : 'FALSE'}',
      'END:VEVENT',
      'END:VCALENDAR'
    ];
    // Fold by UTF-8 octets, without splitting a Unicode codepoint (RFC 5545).
    String fold(String line) {
      final out = StringBuffer();
      var count = 0;
      for (final rune in line.runes) {
        final char = String.fromCharCode(rune);
        final bytes = utf8.encode(char).length;
        if (count + bytes > 75) {
          out.write('\r\n ');
          count = 1;
        }
        out.write(char);
        count += bytes;
      }
      return out.toString();
    }

    return '${lines.map(fold).join('\r\n')}\r\n';
  }
}
