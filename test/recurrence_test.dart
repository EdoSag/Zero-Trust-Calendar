import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/recurrence.dart';

List<DateTime> first(String rule, DateTime start, int n) =>
    RecurrenceRule.tryParse(rule)!.occurrences(start).take(n).toList();

void main() {
  test('parses and writes rules', () {
    final r = RecurrenceRule.tryParse('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=6')!;
    expect(r.frequency, Frequency.weekly);
    expect(r.interval, 2);
    expect(r.count, 6);
    expect(r.byDay, [const WeekdayNum(1), const WeekdayNum(3)]);
    expect(r.toString(), 'FREQ=WEEKLY;INTERVAL=2;COUNT=6;BYDAY=MO,WE');
    expect(RecurrenceRule.tryParse('FREQ=HOURLY'), isNull);
    expect(WeekdayNum.parse('-1FR'), const WeekdayNum(5, -1));
  });

  test('daily with count', () {
    final s = DateTime(2026, 11, 10, 9);
    expect(first('FREQ=DAILY;COUNT=3', s, 10), [
      DateTime(2026, 11, 10, 9),
      DateTime(2026, 11, 11, 9),
      DateTime(2026, 11, 12, 9),
    ]);
  });

  test('weekly on several days, every other week', () {
    final s = DateTime(2026, 11, 9, 10); // Monday
    expect(first('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,TH', s, 4), [
      DateTime(2026, 11, 9, 10),
      DateTime(2026, 11, 12, 10),
      DateTime(2026, 11, 23, 10),
      DateTime(2026, 11, 26, 10),
    ]);
  });

  test('every weekday', () {
    final s = DateTime(2026, 11, 13, 8); // Friday
    expect(first('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR', s, 3), [
      DateTime(2026, 11, 13, 8),
      DateTime(2026, 11, 16, 8),
      DateTime(2026, 11, 17, 8),
    ]);
  });

  test('monthly on the 31st skips short months', () {
    final s = DateTime(2026, 1, 31);
    expect(first('FREQ=MONTHLY', s, 3), [
      DateTime(2026, 1, 31),
      DateTime(2026, 3, 31),
      DateTime(2026, 5, 31),
    ]);
  });

  test('monthly on the second Tuesday and the last Friday', () {
    expect(first('FREQ=MONTHLY;BYDAY=2TU', DateTime(2026, 11, 10, 18), 3), [
      DateTime(2026, 11, 10, 18),
      DateTime(2026, 12, 8, 18),
      DateTime(2027, 1, 12, 18),
    ]);
    expect(first('FREQ=MONTHLY;BYDAY=-1FR', DateTime(2026, 11, 27), 3), [
      DateTime(2026, 11, 27),
      DateTime(2026, 12, 25),
      DateTime(2027, 1, 29),
    ]);
    // Outlook's form: BYDAY with BYSETPOS.
    expect(first('FREQ=MONTHLY;BYDAY=FR;BYSETPOS=-1', DateTime(2026, 11, 27), 2), [
      DateTime(2026, 11, 27),
      DateTime(2026, 12, 25),
    ]);
  });

  test('last day of the month', () {
    expect(first('FREQ=MONTHLY;BYMONTHDAY=-1', DateTime(2027, 1, 31), 3), [
      DateTime(2027, 1, 31),
      DateTime(2027, 2, 28),
      DateTime(2027, 3, 31),
    ]);
  });

  test('yearly, Feb 29 only in leap years', () {
    expect(first('FREQ=YEARLY', DateTime(2028, 2, 29), 2), [
      DateTime(2028, 2, 29),
      DateTime(2032, 2, 29),
    ]);
    expect(first('FREQ=YEARLY;BYMONTH=11;BYDAY=4TH', DateTime(2026, 11, 26), 2), [
      DateTime(2026, 11, 26),
      DateTime(2027, 11, 25),
    ]);
  });

  test('until is inclusive', () {
    final r = RecurrenceRule.tryParse('FREQ=DAILY;UNTIL=20261112')!;
    expect(r.occurrences(DateTime(2026, 11, 10, 9)).toList(), [
      DateTime(2026, 11, 10, 9),
      DateTime(2026, 11, 11, 9),
      DateTime(2026, 11, 12, 9),
    ]);
  });

  test('between skips exceptions and keeps local time across DST', () {
    final r = RecurrenceRule.tryParse('FREQ=WEEKLY')!;
    final s = DateTime(2026, 10, 19, 9);
    final got = r.between(
      s,
      DateTime(2026, 10, 1),
      DateTime(2026, 11, 10),
      exclude: {DateTime(2026, 10, 26, 9)},
    );
    expect(got, [
      DateTime(2026, 10, 19, 9),
      DateTime(2026, 11, 2, 9),
      DateTime(2026, 11, 9, 9),
    ]);
    expect(got.every((t) => t.hour == 9), isTrue);
  });

  test('a rule that never matches ends', () {
    final r = RecurrenceRule.tryParse('FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30')!;
    expect(r.occurrences(DateTime(2026, 2, 1)).take(5).toList(), [DateTime(2026, 2, 1)]);
  });
}
