import '../domain/models.dart';

class CalendarFailure implements Exception {
  const CalendarFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class CalendarConflict extends CalendarFailure {
  const CalendarConflict(super.message);
}

abstract class CalendarConnector {
  CalendarProvider get provider;
  Future<CalendarAccount> connect();
  Future<void> disconnect();
  Future<List<RemoteCalendar>> calendars();
  Future<List<TodoCategory>> categories(
      CalendarAccount account, List<RemoteCalendar> calendars);
  Future<List<Todo>> events(CalendarAccount account, RemoteCalendar calendar,
      DateTime from, DateTime until);
  Future<Todo> push(CalendarAccount account, Todo todo);
  Future<void> delete(CalendarAccount account, Todo todo);
}

String remotePrefix(CalendarAccount account) =>
    '${account.provider.name}:${account.accountId}:';
String calendarCategoryKey(CalendarAccount account, String calendarId) =>
    '${remotePrefix(account)}calendar:$calendarId';
String eventKey(CalendarAccount account, String calendarId, String eventId) =>
    '${remotePrefix(account)}event:$calendarId:$eventId';
