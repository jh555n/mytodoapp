import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dayweave/app_controller.dart';
import 'package:dayweave/data/store.dart';
import 'package:dayweave/domain/models.dart';
import 'package:dayweave/domain/recurrence.dart';
import 'package:dayweave/services/calendars.dart';

class FakeConnector implements CalendarConnector {
  @override
  CalendarProvider get provider => CalendarProvider.google;
  List<Todo> remote = [];
  bool conflictOnPush = false;
  bool disconnected = false;
  int writes = 0;
  @override
  Future<CalendarAccount> connect() async => const CalendarAccount(
      provider: CalendarProvider.google,
      accountId: 'account',
      displayName: 'test@example.com');
  @override
  Future<void> disconnect() async {
    disconnected = true;
  }

  @override
  Future<List<RemoteCalendar>> calendars() async => const [
        RemoteCalendar(
            id: 'calendar', name: '외부 업무', color: 0xFF2B8C78, writable: true)
      ];
  @override
  Future<List<TodoCategory>> categories(
          CalendarAccount account, List<RemoteCalendar> calendars) async =>
      calendars
          .map((calendar) => TodoCategory(
              id: calendarCategoryKey(account, calendar.id),
              name: calendar.name,
              colorValue: calendar.color,
              remoteKey: calendarCategoryKey(account, calendar.id)))
          .toList();
  @override
  Future<List<Todo>> events(CalendarAccount account, RemoteCalendar calendar,
          DateTime from, DateTime until) async =>
      remote;
  @override
  Future<Todo> push(CalendarAccount account, Todo todo) async {
    if (conflictOnPush) throw const CalendarConflict('동시에 수정됨');
    writes++;
    final updated = todo.change({
      'remoteKey': todo.remoteKey ?? eventKey(account, 'calendar', todo.id),
      'remoteRevision': 'new',
      'dirty': false
    });
    remote.removeWhere((t) => t.remoteKey == updated.remoteKey);
    remote.add(updated);
    return updated;
  }

  @override
  Future<void> delete(CalendarAccount account, Todo todo) async {
    remote.removeWhere((t) => t.remoteKey == todo.remoteKey);
  }
}

void main() {
  sqfliteFfiInit();
  late TodoStore store;
  late AppController controller;
  late FakeConnector connector;
  setUp(() async {
    store = await TodoStore.open(
        factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    connector = FakeConnector();
    controller = AppController(
        store: store,
        engine: RecurrenceEngine(HolidayCalendar({}, coveredYears: {2026})),
        connectors: {CalendarProvider.google: connector});
    await controller.load();
  });
  tearDown(() async {
    controller.dispose();
    await store.close();
  });

  test('unconnected Todo writes never contact a calendar', () async {
    await controller.saveTodo(
        title: '기기 내 할 일', notes: '로컬', categoryId: 'work');
    expect(controller.todos.single.title, '기기 내 할 일');
    expect(connector.writes, 0);
    expect(controller.accounts, isEmpty);
  });
  test('recurring completion affects only the selected original occurrence',
      () async {
    final now = dateOnly(DateTime.now());
    await controller.saveTodo(
        title: '매일',
        notes: '',
        anchor: now,
        repeat: const RepeatRule(unit: RepeatUnit.day));
    final items =
        controller.occurrences(now, DateTime(now.year, now.month, now.day + 2));
    expect(items, hasLength(2));
    await controller.toggle(items.first);
    final after = controller.occurrences(
        now, DateTime(now.year, now.month, now.day + 2),
        showCompleted: true);
    expect(after.where((o) => o.completed), hasLength(1));
    expect(controller.todos.single.completed, isFalse);
  });
  test(
      'import, category colour, external deletion, and retained disconnect work',
      () async {
    await controller.connect(CalendarProvider.google);
    final now = DateTime.now();
    connector.remote = [
      Todo(
          id: 'remote',
          title: '외부 일정',
          createdAt: now,
          updatedAt: now,
          startsAt: now,
          anchorAt: now,
          provider: CalendarProvider.google,
          calendarId: 'calendar',
          remoteKey: 'google:account:event:calendar:remote',
          readOnly: true)
    ];
    await controller.selectCalendar(CalendarProvider.google, 'calendar', true);
    expect(controller.todos.single.title, '외부 일정');
    expect(controller.categories.last.colorValue, 0xFF2B8C78);
    await controller.disconnect(CalendarProvider.google, keepImported: true);
    expect(connector.disconnected, isTrue);
    expect(controller.todos.single.provider, isNull);
    expect(controller.todos.single.remoteKey, isNull);
    expect(controller.todos.single.readOnly, isFalse);
  });
  test(
      'remote deletion removes a clean imported event within the fetched range',
      () async {
    await controller.connect(CalendarProvider.google);
    final now = DateTime.now();
    connector.remote = [
      Todo(
          id: 'remote',
          title: '외부 일정',
          createdAt: now,
          updatedAt: now,
          startsAt: now,
          provider: CalendarProvider.google,
          calendarId: 'calendar',
          remoteKey: 'google:account:event:calendar:remote',
          readOnly: true)
    ];
    await controller.selectCalendar(CalendarProvider.google, 'calendar', true);
    connector.remote = [];
    await controller.sync();
    expect(controller.todos, isEmpty);
  });
  test('conflict retains local edits and resolves only after a user choice',
      () async {
    await controller.connect(CalendarProvider.google);
    await controller.selectCalendar(CalendarProvider.google, 'calendar', true);
    final now = DateTime.now();
    final local = Todo(
        id: 'local',
        title: '기기 수정',
        createdAt: now,
        updatedAt: now,
        startsAt: now,
        provider: CalendarProvider.google,
        calendarId: 'calendar',
        remoteKey: 'google:account:event:calendar:event',
        remoteRevision: 'old',
        dirty: true);
    await store.saveTodo(local);
    connector.remote = [
      local.change({
        'id': 'remote',
        'title': '외부 수정',
        'dirty': false,
        'remoteRevision': 'remote-new'
      })
    ];
    connector.conflictOnPush = true;
    await controller.sync();
    expect(controller.todos.single.title, '기기 수정');
    expect(controller.conflicts, hasLength(1));
    await controller.resolveConflict('local', keepLocal: false);
    expect(controller.todos.single.title, '외부 수정');
    expect(controller.conflicts, isEmpty);
  });
}
