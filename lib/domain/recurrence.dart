import 'models.dart';

class HolidayCalendar {
  HolidayCalendar(Map<String, String> holidays,
      {required Set<int> coveredYears})
      : holidays = Map.unmodifiable(holidays),
        coveredYears = Set.unmodifiable(coveredYears);
  final Map<String, String> holidays;
  final Set<int> coveredYears;
  final Map<bool, int> _shiftBounds = {};
  bool isHoliday(DateTime date, {required bool weekends}) =>
      holidays.containsKey(dayKey(date)) ||
      (weekends && date.weekday >= DateTime.saturday);

  int maximumShift({required bool weekends}) {
    if (_shiftBounds.containsKey(weekends)) return _shiftBounds[weekends]!;
    var maximum = weekends ? 2 : 0;
    for (final year in coveredYears) {
      var streak = 0;
      for (var at = DateTime(year);
          at.year == year;
          at = DateTime(at.year, at.month, at.day + 1)) {
        streak = isHoliday(at, weekends: weekends) ? streak + 1 : 0;
        if (streak > maximum) maximum = streak;
      }
    }
    // Extra room for a closure crossing the boundary of consecutive covered years.
    final bound = maximum * 2 + 2;
    _shiftBounds[weekends] = bound;
    return bound;
  }

  DateTime shift(DateTime date, RepeatRule rule) {
    if (rule.shift == HolidayShift.keep) return date;
    if (!coveredYears.contains(date.year)) {
      throw StateError('${date.year}년 공휴일 정보가 없습니다. 날짜 이동을 확정할 수 없습니다.');
    }
    final direction = rule.shift == HolidayShift.before ? -1 : 1;
    var shifted = date;
    for (var i = 0; i < 366; i++) {
      if (!coveredYears.contains(shifted.year)) {
        throw StateError('${shifted.year}년 공휴일 정보가 필요합니다.');
      }
      if (!isHoliday(shifted, weekends: rule.weekendsAreHolidays)) {
        return shifted;
      }
      shifted = DateTime(shifted.year, shifted.month, shifted.day + direction,
          date.hour, date.minute);
    }
    throw StateError('업무일을 찾지 못했습니다. 공휴일 설정을 확인하세요.');
  }
}

class Occurrence {
  const Occurrence(this.anchor, this.scheduled);
  final DateTime anchor;
  final DateTime scheduled;
}

class RecurrenceEngine {
  const RecurrenceEngine(this.holidays);
  final HolidayCalendar holidays;

  DateTime anchorAt(DateTime seed, RepeatRule rule, int index) {
    if (rule.interval < 1 || index < 0) {
      throw ArgumentError('Invalid recurrence interval/index');
    }
    final step = rule.interval * index;
    DateTime clamped(int year, int month) {
      final normalized = DateTime(year, month);
      final last = DateTime(normalized.year, normalized.month + 1, 0).day;
      return DateTime(normalized.year, normalized.month,
          seed.day > last ? last : seed.day, seed.hour, seed.minute);
    }

    switch (rule.unit) {
      case RepeatUnit.none:
        return seed;
      case RepeatUnit.day:
        return DateTime(
            seed.year, seed.month, seed.day + step, seed.hour, seed.minute);
      case RepeatUnit.week:
        return DateTime(
            seed.year, seed.month, seed.day + 7 * step, seed.hour, seed.minute);
      case RepeatUnit.month:
        return clamped(seed.year, seed.month + step);
      case RepeatUnit.year:
        return clamped(seed.year + step, seed.month);
    }
  }

  List<Occurrence> between(Todo todo, DateTime from, DateTime until) {
    final seed = todo.anchorAt ?? todo.startsAt;
    if (seed == null) return [];
    final result = <Occurrence>[];
    // Start near the requested interval so old daily series don't require scanning years.
    final shiftMargin = todo.repeat.shift == HolidayShift.keep
        ? 0
        : holidays.maximumShift(weekends: todo.repeat.weekendsAreHolidays);
    final margin = DateTime(from.year, from.month, from.day - shiftMargin);
    var start = 0;
    if (margin.isAfter(seed)) {
      final days = margin.difference(seed).inDays;
      switch (todo.repeat.unit) {
        case RepeatUnit.day:
          start = days ~/ todo.repeat.interval;
          break;
        case RepeatUnit.week:
          start = days ~/ (7 * todo.repeat.interval);
          break;
        case RepeatUnit.month:
          start =
              ((margin.year - seed.year) * 12 + margin.month - seed.month) ~/
                  todo.repeat.interval;
          break;
        case RepeatUnit.year:
          start = (margin.year - seed.year) ~/ todo.repeat.interval;
          break;
        case RepeatUnit.none:
          start = 0;
          break;
      }
      if (start > 0) start--;
    }
    final endMargin =
        DateTime(until.year, until.month, until.day + shiftMargin);
    for (var i = start; i < start + 10000; i++) {
      final anchor = anchorAt(seed, todo.repeat, i);
      if (anchor.isAfter(endMargin)) break;
      // Don't demand unsupported holiday years far outside the visible window.
      if (anchor.isBefore(margin)) {
        if (todo.repeat.unit == RepeatUnit.none) break;
        continue;
      }
      if (anchor.isAfter(until) && todo.repeat.shift != HolidayShift.before) {
        break;
      }
      if (anchor.isBefore(from) && todo.repeat.shift != HolidayShift.after) {
        if (todo.repeat.unit == RepeatUnit.none) break;
        continue;
      }
      final scheduled = holidays.shift(anchor, todo.repeat);
      if (!scheduled.isBefore(from) && scheduled.isBefore(until)) {
        result.add(Occurrence(anchor, scheduled));
      }
      if (todo.repeat.unit == RepeatUnit.none) break;
    }
    return result;
  }

  Occurrence next(Todo todo, DateTime currentAnchor) {
    final seed = todo.anchorAt ?? todo.startsAt!;
    for (var i = 1; i < 10000; i++) {
      final anchor = anchorAt(seed, todo.repeat, i);
      if (anchor.isAfter(currentAnchor)) {
        return Occurrence(anchor, holidays.shift(anchor, todo.repeat));
      }
    }
    throw StateError('다음 반복 날짜를 찾지 못했습니다.');
  }
}
