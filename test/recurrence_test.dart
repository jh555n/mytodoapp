import 'package:flutter_test/flutter_test.dart';
import 'package:dayweave/domain/models.dart';
import 'package:dayweave/domain/recurrence.dart';

void main() {
  final holidays = HolidayCalendar({'2026-05-05': '어린이날', '2026-10-09': '한글날'},
      coveredYears: {2026});
  final engine = RecurrenceEngine(holidays);
  Todo series(DateTime seed, RepeatRule rule) => Todo(
      id: 'series',
      title: '반복',
      createdAt: seed,
      updatedAt: seed,
      startsAt: seed,
      anchorAt: seed,
      repeat: rule);

  test('monthly anchors recover the original day after a short month', () {
    final seed = DateTime(2026, 1, 31, 9, 30);
    const rule = RepeatRule(unit: RepeatUnit.month);
    expect(engine.anchorAt(seed, rule, 1), DateTime(2026, 2, 28, 9, 30));
    expect(engine.anchorAt(seed, rule, 2), DateTime(2026, 3, 31, 9, 30));
  });
  test('yearly leap-day anchors recover Feb 29 in the next leap year', () {
    final seed = DateTime(2024, 2, 29);
    const rule = RepeatRule(unit: RepeatUnit.year);
    expect(engine.anchorAt(seed, rule, 1), DateTime(2025, 2, 28));
    expect(engine.anchorAt(seed, rule, 4), DateTime(2028, 2, 29));
  });
  test('holiday shift walks through an adjacent weekend, preserving time', () {
    const rule = RepeatRule(shift: HolidayShift.after);
    expect(holidays.shift(DateTime(2026, 10, 9, 14, 10), rule),
        DateTime(2026, 10, 12, 14, 10));
    expect(
        holidays.shift(DateTime(2026, 10, 9, 14, 10),
            const RepeatRule(shift: HolidayShift.before)),
        DateTime(2026, 10, 8, 14, 10));
  });
  test('weekends may stay while public holidays move', () {
    expect(
        holidays.shift(
            DateTime(2026, 10, 10),
            const RepeatRule(
                shift: HolidayShift.after, weekendsAreHolidays: false)),
        DateTime(2026, 10, 10));
  });
  test('shifted occurrence does not change subsequent monthly anchors', () {
    final todo = series(DateTime(2026, 5, 5, 9),
        const RepeatRule(unit: RepeatUnit.month, shift: HolidayShift.after));
    final next = engine.next(todo, DateTime(2026, 5, 5, 9));
    expect(next.anchor, DateTime(2026, 6, 5, 9));
    expect(next.scheduled, DateTime(2026, 6, 5, 9));
  });
  test('unknown holiday years are rejected instead of silently guessed', () {
    expect(
        () => holidays.shift(
            DateTime(2027, 1, 1), const RepeatRule(shift: HolidayShift.after)),
        throwsStateError);
  });
  test('each visible daily occurrence keeps its original completion identity',
      () {
    final todo = series(DateTime(2026, 10, 9),
        const RepeatRule(unit: RepeatUnit.day, shift: HolidayShift.after));
    final occurrences =
        engine.between(todo, DateTime(2026, 10, 12), DateTime(2026, 10, 13));
    expect(occurrences.map((o) => o.anchor).toSet(), {
      DateTime(2026, 10, 9),
      DateTime(2026, 10, 10),
      DateTime(2026, 10, 11),
      DateTime(2026, 10, 12)
    });
    expect(occurrences.every((o) => o.scheduled == DateTime(2026, 10, 12)),
        isTrue);
  });
}
