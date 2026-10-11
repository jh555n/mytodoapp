import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'data/store.dart';
import 'domain/models.dart';
import 'domain/recurrence.dart';
import 'services/calendars.dart';
import 'services/notifications.dart';

class TodoOccurrence {
  const TodoOccurrence(this.todo, this.anchor, this.at, this.completed);
  final Todo todo;
  final DateTime? anchor;
  final DateTime? at;
  final bool completed;
}

class ConflictPair {
  const ConflictPair(this.local, this.remote);
  final Todo local;
  final Todo remote;
}

class AppController extends ChangeNotifier {
  AppController(
      {required this.store,
      required this.engine,
      required this.connectors,
      this.reminders});
  final TodoStore store;
  final RecurrenceEngine engine;
  final Map<CalendarProvider, CalendarConnector> connectors;
  final ReminderService? reminders;
  List<Todo> todos = [];
  List<TodoCategory> categories = [];
  Set<String> completions = {};
  Map<CalendarProvider, CalendarAccount> accounts = {};
  Map<CalendarProvider, List<RemoteCalendar>> remoteCalendars = {};
  Map<CalendarProvider, Set<String>> selectedCalendars = {};
  bool syncing = false;
  bool notificationsEnabled = false;
  String? warning;
  DateTime? lastSynced;
  final Map<String, ConflictPair> conflicts = {};

  static Future<HolidayCalendar> loadHolidays() async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/holidays/kr_2026.json'))
            as Map<String, dynamic>;
    return HolidayCalendar(Map<String, String>.from(json['dates'] as Map),
        coveredYears: {(json['year'] as num).toInt()});
  }

  Future<void> load() async {
    todos = await store.todos();
    categories = await store.categories();
    completions = await store.completions();
    if (categories.isEmpty) {
      for (final category in const [
        TodoCategory(id: 'work', name: '업무', colorValue: 0xFF5B5BD6),
        TodoCategory(
            id: 'personal',
            name: '개인',
            colorValue: 0xFF2B8C78,
            icon: 'personal'),
        TodoCategory(
            id: 'health', name: '건강', colorValue: 0xFFE08A44, icon: 'health'),
      ]) {
        await store.saveCategory(category);
      }
      categories = await store.categories();
    }
    final raw = await store.value('accounts') as List? ?? [];
    accounts = {
      for (final entry in raw)
        CalendarProvider.values.byName((entry as Map)['provider'] as String):
            CalendarAccount.fromJson(Map<String, dynamic>.from(entry))
    };
    for (final provider in accounts.keys) {
      selectedCalendars[provider] = Set<String>.from(
          await store.value('selected.${provider.name}') as List? ?? []);
    }
    notificationsEnabled = await store.value('notifications') as bool? ?? false;
    notifyListeners();
  }

  Future<void> reload() async {
    todos = await store.todos();
    categories = await store.categories();
    completions = await store.completions();
    notifyListeners();
  }

  TodoCategory? category(String? id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  String errorMessage(Object error) {
    if (error is CalendarFailure) return error.message;
    if (error is StateError) return error.message.toString();
    if (error is PlatformException) {
      return error.message ?? '기기 설정과 접근 권한을 확인하세요.';
    }
    return '작업을 완료하지 못했습니다. 네트워크와 기기 권한을 확인하고 다시 시도하세요.';
  }

  Future<void> scheduleReminders() async {
    if (!notificationsEnabled || reminders == null) return;
    try {
      await reminders!.rebuild(todos, completions, engine);
    } catch (e) {
      warning = '데이터는 저장됐지만 알림을 갱신하지 못했습니다. ${errorMessage(e)}';
      notifyListeners();
    }
  }

  Future<void> enableNotifications(bool enabled) async {
    if (enabled && !(await reminders?.requestPermission() ?? false)) {
      throw const CalendarFailure('알림 권한이 꺼져 있습니다. 기기 설정에서 허용하세요.');
    }
    notificationsEnabled = enabled;
    await store.setValue('notifications', enabled);
    if (enabled) {
      await scheduleReminders();
    } else {
      await reminders?.cancelAll();
    }
    notifyListeners();
  }

  List<TodoOccurrence> occurrences(DateTime from, DateTime until,
      {bool includeUndated = false,
      String? categoryId,
      String search = '',
      bool showCompleted = false}) {
    final result = <TodoOccurrence>[];
    for (final todo in todos) {
      if (todo.deleted ||
          (categoryId != null && todo.categoryId != categoryId)) {
        continue;
      }
      if (search.isNotEmpty &&
          !('${todo.title} ${todo.notes}')
              .toLowerCase()
              .contains(search.toLowerCase())) {
        continue;
      }
      if (todo.startsAt == null) {
        if (includeUndated && (showCompleted || !todo.completed)) {
          result.add(TodoOccurrence(todo, null, null, todo.completed));
        }
        continue;
      }
      if (todo.repeat.unit == RepeatUnit.none) {
        final at = todo.startsAt!;
        if (!at.isBefore(from) &&
            at.isBefore(until) &&
            (showCompleted || !todo.completed)) {
          result.add(
              TodoOccurrence(todo, todo.anchorAt ?? at, at, todo.completed));
        }
      } else {
        try {
          for (final occurrence in engine.between(todo, from, until)) {
            final done = completions
                .contains('${todo.id}@${occurrence.anchor.toIso8601String()}');
            if (showCompleted || !done) {
              result.add(TodoOccurrence(
                  todo, occurrence.anchor, occurrence.scheduled, done));
            }
          }
        } on StateError {
          // Keep the series visible; never silently assign an unverified holiday date.
          final at = todo.startsAt!;
          if (!at.isBefore(from) && at.isBefore(until)) {
            result.add(
                TodoOccurrence(todo, todo.anchorAt ?? at, at, todo.completed));
          }
        }
      }
    }
    result.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      final priority = b.todo.priority.compareTo(a.todo.priority);
      if (priority != 0) return priority;
      return (a.at ?? until).compareTo(b.at ?? until);
    });
    return result;
  }

  Future<void> saveTodo(
      {Todo? existing,
      required String title,
      required String notes,
      String? categoryId,
      DateTime? anchor,
      bool allDay = true,
      int priority = 0,
      int? reminderMinutes,
      RepeatRule repeat = const RepeatRule(),
      CalendarProvider? provider,
      String? calendarId,
      List<ChecklistStep> steps = const []}) async {
    if (title.trim().isEmpty) throw const CalendarFailure('할 일 제목을 입력하세요.');
    if (existing?.readOnly ?? false) {
      throw const CalendarFailure('외부 일정은 원래 캘린더에서 수정하세요.');
    }
    if (repeat.unit != RepeatUnit.none && anchor == null) {
      throw const CalendarFailure('반복 할 일의 시작 날짜가 필요합니다.');
    }
    if (provider != null && (anchor == null || calendarId == null)) {
      throw const CalendarFailure('캘린더 전송에는 날짜와 대상 캘린더가 필요합니다.');
    }
    if (provider != null && repeat.unit != RepeatUnit.none) {
      throw const CalendarFailure('반복 일정은 현재 로컬 저장을 지원합니다. 저장 위치를 기기로 선택하세요.');
    }
    final rule = repeat.unit == RepeatUnit.none ? const RepeatRule() : repeat;
    final scheduled =
        anchor == null ? null : engine.holidays.shift(anchor, rule);
    final now = DateTime.now();
    final todo = Todo(
        id: existing?.id ?? const Uuid().v4(),
        title: title.trim(),
        notes: notes.trim(),
        categoryId: categoryId,
        anchorAt: anchor,
        startsAt: scheduled,
        allDay: allDay,
        priority: priority,
        reminderMinutes: reminderMinutes,
        repeat: rule,
        steps: steps,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        completed: existing?.completed ?? false,
        provider: provider,
        calendarId: calendarId,
        remoteKey: existing?.remoteKey,
        remoteRevision: existing?.remoteRevision,
        dirty: provider != null);
    await store.saveTodo(todo);
    await reload();
    await scheduleReminders();
    if (provider != null) await sync();
  }

  Future<void> toggle(TodoOccurrence occurrence) async {
    final todo = occurrence.todo;
    if (todo.readOnly) return;
    if (todo.repeat.unit != RepeatUnit.none) {
      await store.complete(todo.id, occurrence.anchor!, !occurrence.completed);
    } else {
      await store.saveTodo(todo.change({
        'completed': !todo.completed,
        'updatedAt': DateTime.now().toIso8601String(),
        'dirty': todo.provider != null
      }));
    }
    await reload();
    await scheduleReminders();
    if (todo.provider != null) await sync();
  }

  Future<void> delete(Todo todo) async {
    if (todo.readOnly) throw const CalendarFailure('외부 일정은 원래 캘린더에서 삭제하세요.');
    if (todo.remoteKey != null) {
      await store.saveTodo(todo.change({'deleted': true, 'dirty': true}));
    } else {
      await store.deleteTodo(todo.id);
    }
    await reload();
    await scheduleReminders();
    if (todo.provider != null) await sync();
  }

  Future<void> saveCategory(String name, int color, String icon,
      {TodoCategory? existing}) async {
    if (name.trim().isEmpty) throw const CalendarFailure('카테고리 이름을 입력하세요.');
    if (existing?.remoteKey != null) {
      throw const CalendarFailure('연동 카테고리 이름과 색상은 원래 캘린더에서 변경하세요.');
    }
    await store.saveCategory(TodoCategory(
        id: existing?.id ?? const Uuid().v4(),
        name: name.trim(),
        colorValue: color,
        icon: icon));
    await reload();
  }

  Future<void> connect(CalendarProvider provider) async {
    if (syncing || accounts.containsKey(provider)) {
      throw const CalendarFailure('기존 연결을 먼저 해제하세요.');
    }
    final connector = connectors[provider]!;
    final account = await connector.connect();
    List<RemoteCalendar> calendars;
    try {
      calendars = await connector.calendars();
    } catch (_) {
      try {
        await connector.disconnect();
      } catch (_) {/* Preserve the original connection failure. */}
      rethrow;
    }
    accounts[provider] = account;
    remoteCalendars[provider] = calendars;
    selectedCalendars[provider] = {};
    await store.setValue(
        'accounts', accounts.values.map((a) => a.toJson()).toList());
    await store.setValue('selected.${provider.name}', <String>[]);
    notifyListeners();
  }

  Future<void> selectCalendar(
      CalendarProvider provider, String id, bool selected) async {
    final ids = selectedCalendars.putIfAbsent(provider, () => {});
    selected ? ids.add(id) : ids.remove(id);
    await store.setValue('selected.${provider.name}', ids.toList());
    notifyListeners();
    await sync();
  }

  Future<void> disconnect(CalendarProvider provider,
      {required bool keepImported}) async {
    if (syncing) throw const CalendarFailure('동기화 완료 후 연결을 해제하세요.');
    await connectors[provider]!.disconnect();
    conflicts.removeWhere((_, pair) => pair.local.provider == provider);
    for (final todo in todos.where((t) => t.provider == provider)) {
      if (todo.deleted) {
        await store.deleteTodo(todo.id);
      } else if (keepImported) {
        await store.saveTodo(todo.change({
          'provider': null,
          'calendarId': null,
          'remoteKey': null,
          'remoteRevision': null,
          'dirty': false,
          'deleted': false,
          'readOnly': false
        }));
      } else {
        await store.deleteTodo(todo.id);
      }
    }
    final prefix = remotePrefix(accounts[provider]!);
    for (final category in categories
        .where((category) => category.remoteKey?.startsWith(prefix) ?? false)) {
      await store.saveCategory(TodoCategory(
          id: category.id,
          name: category.name,
          colorValue: category.colorValue,
          icon: category.icon));
    }
    accounts.remove(provider);
    remoteCalendars.remove(provider);
    selectedCalendars.remove(provider);
    await store.setValue(
        'accounts', accounts.values.map((a) => a.toJson()).toList());
    await store.setValue('selected.${provider.name}', <String>[]);
    await reload();
    await scheduleReminders();
  }

  Future<void> resolveConflict(String id, {required bool keepLocal}) async {
    final pair = conflicts[id];
    if (pair == null || syncing) return;
    if (keepLocal) {
      await store.saveTodo(pair.local.change({
        'remoteRevision': pair.remote.remoteRevision,
        'remoteKey': pair.remote.remoteKey,
        'dirty': true
      }));
    } else {
      await store.saveTodo(pair.remote.change({
        'id': pair.local.id,
        'dirty': false,
        'priority': pair.local.priority,
        'reminderMinutes': pair.local.reminderMinutes,
        'steps': pair.local.toJson()['steps']
      }));
    }
    conflicts.remove(id);
    await reload();
    await sync();
  }

  Future<void> sync() async {
    if (syncing || accounts.isEmpty) return;
    syncing = true;
    warning = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final from = DateTime(now.year - 1, now.month);
      final until = DateTime(now.year + 1, now.month + 1);
      for (final account in accounts.values) {
        final connector = connectors[account.provider]!;
        final calendars = await connector.calendars();
        remoteCalendars[account.provider] = calendars;
        final selected = calendars
            .where((c) =>
                selectedCalendars[account.provider]?.contains(c.id) ?? false)
            .toList();
        for (final category in await connector.categories(account, selected)) {
          final old = this.category(category.id);
          await store.saveCategory(TodoCategory(
              id: category.id,
              name: category.name,
              colorValue: category.colorValue,
              icon: old?.icon ?? category.icon,
              remoteKey: category.remoteKey));
        }
        for (final calendar in selected) {
          // Push before the pull; If-Match rejects an externally modified resource.
          for (final todo in (await store.todos()).where((t) =>
              t.provider == account.provider &&
              t.calendarId == calendar.id &&
              t.dirty)) {
            if (conflicts.containsKey(todo.id)) continue;
            try {
              if (todo.deleted) {
                await connector.delete(account, todo);
                await store.deleteTodo(todo.id);
              } else {
                await store.saveTodo(await connector.push(account, todo));
              }
            } on CalendarConflict {
              // Continue with the pull so the user can compare both versions.
              warning = '양쪽에서 수정된 일정이 있습니다. 설정에서 변경 내용을 선택하세요.';
            }
          }
          final incoming =
              await connector.events(account, calendar, from, until);
          final current = await store.todos();
          final incomingKeys = incoming.map((t) => t.remoteKey).toSet();
          for (final remote in incoming) {
            final matches = current
                .where((t) =>
                    t.remoteKey == remote.remoteKey ||
                    (t.id == remote.id &&
                        t.provider == remote.provider &&
                        t.calendarId == remote.calendarId))
                .toList();
            final local = matches.isEmpty ? null : matches.first;
            if (local?.dirty ?? false) {
              conflicts[local!.id] = ConflictPair(local, remote);
              continue;
            }
            await store.saveTodo(local == null
                ? remote
                : remote.change({
                    'id': local.id,
                    'createdAt': local.createdAt.toIso8601String(),
                    'reminderMinutes': local.reminderMinutes,
                    'categoryId': local.categoryId != null &&
                            category(local.categoryId)?.remoteKey == null
                        ? local.categoryId
                        : remote.categoryId,
                    'priority': local.priority,
                    'steps': local.toJson()['steps']
                  }));
          }
          // Remove absent events only inside the successfully fetched time window.
          for (final local in current.where((t) =>
              t.provider == account.provider &&
              t.calendarId == calendar.id &&
              t.remoteKey != null &&
              !t.dirty &&
              t.startsAt != null &&
              !t.startsAt!.isBefore(from) &&
              t.startsAt!.isBefore(until))) {
            if (!incomingKeys.contains(local.remoteKey)) {
              await store.deleteTodo(local.id);
            }
          }
        }
      }
      lastSynced = DateTime.now();
      if (conflicts.isNotEmpty) {
        warning = '양쪽에서 수정된 일정이 있습니다. 설정에서 변경 내용을 선택하세요.';
      }
    } catch (e) {
      warning = errorMessage(e);
    } finally {
      syncing = false;
      await reload();
      await scheduleReminders();
    }
  }
}
