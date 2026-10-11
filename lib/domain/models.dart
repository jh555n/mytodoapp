import 'package:flutter/material.dart';

enum RepeatUnit { none, day, week, month, year }

enum HolidayShift { keep, before, after }

enum CalendarProvider { google, apple, icloud }

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String dayKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class RepeatRule {
  const RepeatRule(
      {this.unit = RepeatUnit.none,
      this.interval = 1,
      this.shift = HolidayShift.keep,
      this.weekendsAreHolidays = true});
  final RepeatUnit unit;
  final int interval;
  final HolidayShift shift;
  final bool weekendsAreHolidays;
  Map<String, dynamic> toJson() => {
        'unit': unit.name,
        'interval': interval,
        'shift': shift.name,
        'weekends': weekendsAreHolidays
      };
  factory RepeatRule.fromJson(Map<String, dynamic> json) => RepeatRule(
        unit: RepeatUnit.values.byName(json['unit'] as String),
        interval: (json['interval'] as num).toInt(),
        shift: HolidayShift.values.byName(json['shift'] as String),
        weekendsAreHolidays: json['weekends'] as bool,
      );
}

class TodoCategory {
  const TodoCategory(
      {required this.id,
      required this.name,
      required this.colorValue,
      this.icon = 'work',
      this.remoteKey});
  final String id;
  final String name;
  final int colorValue;
  final String icon;
  // Namespaced provider/account/calendar/label identity. Never match by name.
  final String? remoteKey;
  Color get color => Color(colorValue);
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'icon': icon,
        'remoteKey': remoteKey
      };
  factory TodoCategory.fromJson(Map<String, dynamic> json) => TodoCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      colorValue: (json['color'] as num).toInt(),
      icon: json['icon'] as String,
      remoteKey: json['remoteKey'] as String?);
}

class ChecklistStep {
  const ChecklistStep(this.title, {this.completed = false});
  final String title;
  final bool completed;
  Map<String, dynamic> toJson() => {'title': title, 'completed': completed};
}

class Todo {
  const Todo(
      {required this.id,
      required this.title,
      required this.createdAt,
      required this.updatedAt,
      this.notes = '',
      this.categoryId,
      this.startsAt,
      this.anchorAt,
      this.allDay = true,
      this.completed = false,
      this.priority = 0,
      this.reminderMinutes,
      this.repeat = const RepeatRule(),
      this.remoteKey,
      this.remoteRevision,
      this.dirty = false,
      this.deleted = false,
      this.calendarId,
      this.provider,
      this.readOnly = false,
      this.steps = const []});
  final String id;
  final String title;
  final String notes;
  final String? categoryId;
  final DateTime? startsAt;
  // Unshifted occurrence date; repeat generation always uses this anchor.
  final DateTime? anchorAt;
  final bool allDay;
  final bool completed;
  final int priority;
  final int? reminderMinutes;
  final RepeatRule repeat;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? remoteKey;
  final String? remoteRevision;
  final String? calendarId;
  final CalendarProvider? provider;
  final bool dirty;
  final bool deleted;
  final bool readOnly;
  final List<ChecklistStep> steps;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'categoryId': categoryId,
        'startsAt': startsAt?.toIso8601String(),
        'anchorAt': anchorAt?.toIso8601String(),
        'allDay': allDay,
        'completed': completed,
        'priority': priority,
        'reminderMinutes': reminderMinutes,
        'repeat': repeat.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'remoteKey': remoteKey,
        'remoteRevision': remoteRevision,
        'calendarId': calendarId,
        'provider': provider?.name,
        'dirty': dirty,
        'deleted': deleted,
        'readOnly': readOnly,
        'steps': steps.map((step) => step.toJson()).toList(),
      };
  factory Todo.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] == null ? null : DateTime.parse(json[key] as String);
    return Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        notes: json['notes'] as String? ?? '',
        categoryId: json['categoryId'] as String?,
        startsAt: date('startsAt'),
        anchorAt: date('anchorAt'),
        allDay: json['allDay'] as bool? ?? true,
        completed: json['completed'] as bool? ?? false,
        priority: (json['priority'] as num? ?? 0).toInt(),
        reminderMinutes: (json['reminderMinutes'] as num?)?.toInt(),
        repeat: json['repeat'] == null
            ? const RepeatRule()
            : RepeatRule.fromJson(
                Map<String, dynamic>.from(json['repeat'] as Map)),
        createdAt: date('createdAt')!,
        updatedAt: date('updatedAt')!,
        remoteKey: json['remoteKey'] as String?,
        remoteRevision: json['remoteRevision'] as String?,
        calendarId: json['calendarId'] as String?,
        provider: json['provider'] == null
            ? null
            : CalendarProvider.values.byName(json['provider'] as String),
        dirty: json['dirty'] as bool? ?? false,
        deleted: json['deleted'] as bool? ?? false,
        readOnly: json['readOnly'] as bool? ?? false,
        steps: (json['steps'] as List? ?? []).map((raw) {
          final step = raw as Map;
          return ChecklistStep(step['title'] as String,
              completed: step['completed'] as bool);
        }).toList());
  }
  Todo change(Map<String, dynamic> changes) =>
      Todo.fromJson({...toJson(), ...changes});
}

class CalendarAccount {
  const CalendarAccount(
      {required this.provider,
      required this.accountId,
      required this.displayName});
  final CalendarProvider provider;
  final String accountId;
  final String displayName;
  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'accountId': accountId,
        'displayName': displayName
      };
  factory CalendarAccount.fromJson(Map<String, dynamic> json) =>
      CalendarAccount(
          provider: CalendarProvider.values.byName(json['provider'] as String),
          accountId: json['accountId'] as String,
          displayName: json['displayName'] as String);
}

class RemoteCalendar {
  const RemoteCalendar(
      {required this.id,
      required this.name,
      required this.color,
      required this.writable});
  final String id;
  final String name;
  final int color;
  final bool writable;
}

const categoryIcons = <String, IconData>{
  'work': Icons.work_outline_rounded,
  'home': Icons.home_outlined,
  'health': Icons.favorite_border_rounded,
  'study': Icons.menu_book_rounded,
  'shopping': Icons.shopping_bag_outlined,
  'travel': Icons.flight_rounded,
  'personal': Icons.person_outline_rounded,
  'star': Icons.star_outline_rounded,
};
const categoryColors = <int>[
  0xFF5B5BD6,
  0xFF2B8C78,
  0xFFE08A44,
  0xFFCA5772,
  0xFF6389C6,
  0xFF9B72CF,
  0xFF8A9274,
  0xFF667085,
];
