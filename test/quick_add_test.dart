import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/recurrence.dart';
import 'package:zerotrust_calendar/util/quick_add.dart';

void main() {
  // Tuesday 10 November 2026, 10:00.
  final now = DateTime(2026, 11, 10, 10);
  QuickAdd p(String s) => parseQuickAdd(s, now: now);

  test('weekday and time', () {
    final q = p('Lunch with Dana Fri 1pm');
    expect(q.title, 'Lunch with Dana');
    expect(q.start, DateTime(2026, 11, 13, 13));
    expect(q.end, DateTime(2026, 11, 13, 14));
    expect(q.allDay, isFalse);
  });

  test('tomorrow with a range and a place', () {
    final q = p('Dentist tomorrow 9:30-10:15 at Smile Clinic');
    expect(q.title, 'Dentist');
    expect(q.start, DateTime(2026, 11, 11, 9, 30));
    expect(q.end, DateTime(2026, 11, 11, 10, 15));
    expect(q.location, 'Smile Clinic');
  });

  test('1-2pm takes pm for both', () {
    final q = p('Call Mom 1-2pm');
    expect(q.start, DateTime(2026, 11, 10, 13));
    expect(q.end, DateTime(2026, 11, 10, 14));
  });

  test('a time already past today means tomorrow', () {
    expect(p('Gym 7am').start, DateTime(2026, 11, 11, 7));
  });

  test('month day and duration', () {
    final q = p('Team offsite Dec 3 at 9am for 3 hours');
    expect(q.title, 'Team offsite');
    expect(q.start, DateTime(2026, 12, 3, 9));
    expect(q.end, DateTime(2026, 12, 3, 12));
  });

  test('no time is all day', () {
    final q = p('Mike\'s birthday 3/12');
    expect(q.allDay, isTrue);
    expect(q.start, DateTime(2026, 12, 3));
    expect(q.title, 'Mike\'s birthday');
  });

  test('repeats', () {
    final q = p('Standup every Monday 9:30am');
    expect(q.rule!.frequency, Frequency.weekly);
    expect(q.start, DateTime(2026, 11, 16, 9, 30));
    expect(q.title, 'Standup');
  });

  test('Hebrew', () {
    final q = p('ארוחת צהריים עם דנה מחר בשעה 13:00');
    expect(q.title, 'ארוחת צהריים עם דנה');
    expect(q.start, DateTime(2026, 11, 11, 13));
    final w = p('פגישה ביום חמישי ב-10:00');
    expect(w.title, 'פגישה');
    expect(w.start, DateTime(2026, 11, 12, 10));
    final r = p('יוגה כל יום שני 18:00');
    expect(r.rule!.frequency, Frequency.weekly);
    expect(r.title, 'יוגה');
  });

  test('bare "at 5" is the afternoon', () {
    expect(p('Pick up kids at 5').start, DateTime(2026, 11, 10, 17));
    expect(p('Pick up kids at 5').title, 'Pick up kids');
  });
}
