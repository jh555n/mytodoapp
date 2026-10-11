import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:dayweave/domain/models.dart';
import 'package:dayweave/services/icloud_calendar.dart';

void main() {
  tzdata.initializeTimeZones();
  test('Korean text, punctuation, line folding and completion round-trip', () {
    final at = DateTime(2026, 10, 12);
    final todo = Todo(
        id: '123',
        title: List.filled(25, '한국어, 할 일; ').join(),
        notes: '첫 줄\n두 번째 줄 \\ 경로',
        startsAt: at,
        allDay: true,
        completed: true,
        createdAt: at,
        updatedAt: at);
    final encoded = ICalendarCodec.encode(todo);
    expect(
        encoded.split('\r\n').every((line) => utf8.encode(line).length <= 75),
        isTrue);
    final event = ICalendarCodec.parse(encoded).single;
    expect(event['title'], todo.title);
    expect(event['notes'], todo.notes);
    expect(event['allDay'], isTrue);
    expect(event['completed'], isTrue);
    expect(event['startsAt'], at);
  });
  test('TZID and recurrence instances are retained', () {
    final data = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:1\r\n'
        'DTSTART;TZID=Asia/Seoul:20261012T090000\r\n'
        'RECURRENCE-ID;TZID=Asia/Seoul:20261012T090000\r\n'
        'SUMMARY:일정\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
    final event = ICalendarCodec.parse(data).single;
    expect((event['startsAt'] as DateTime).toUtc(), DateTime.utc(2026, 10, 12));
    expect(event['recurrenceId'], '20261012T090000');
  });
}
