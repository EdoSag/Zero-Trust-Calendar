import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/planner/planner_plan.dart';
import 'package:zerotrust_calendar/ui/planner_page.dart';

/// Sunday 22 November 2026, 20:00: the evening before a work week.
final sundayEvening = DateTime(2026, 11, 22, 20);
DateTime mon(int h, [int m = 0]) => DateTime(2026, 11, 23, h, m);
DateTime tue(int h, [int m = 0]) => DateTime(2026, 11, 24, h, m);

const calendars = [
  ZtCalendarInfo.personal,
  ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
];

final lunch = PlannerHabit.lunch('lunch', 'Lunch');

/// Work Monday to Friday 9:00 to 17:00, the Planner on, lunch every day.
final settings = PlannerSettings(
  enabled: true,
  hours: PlannerSettings.defaultHours(DateTime.monday),
  tasks: PlannerTasksChoice.all,
  habits: [lunch],
);

CalendarEvent habitBlock(
  String id,
  String habitId,
  DateTime start,
  int minutes, {
  bool done = false,
  bool skipped = false,
  String title = 'Lunch',
}) => CalendarEvent(
  id: id,
  title: title,
  start: start,
  end: start.add(Duration(minutes: minutes)),
  calendarId: plannerCalendarId,
  extra: {
    'plan': {
      'type': 'habit',
      'habitId': habitId,
      'locked': false,
      'done': done,
      if (skipped) 'skipped': true,
    },
  },
);

CalendarEvent taskBlock(String id, String taskId, DateTime start, int minutes, {bool done = false}) =>
    CalendarEvent(
      id: id,
      title: taskId,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      calendarId: plannerCalendarId,
      taskIds: [taskId],
      extra: {
        'plan': {'type': 'task', 'taskId': taskId, 'locked': false, 'done': done},
      },
    );

/// The stored events once [outcome] is saved.
List<CalendarEvent> apply(List<CalendarEvent> events, PlannerOutcome outcome) => [
  for (final e in events)
    if (!outcome.delete.contains(e.id) && !outcome.save.any((s) => s.id == e.id)) e,
  ...outcome.save,
];

List<CalendarEvent> blocksOf(List<CalendarEvent> events, String itemId, DateTime day) => [
  for (final e in events)
    if (PlanMark.of(e)?.itemId == itemId &&
        e.start.year == day.year &&
        e.start.month == day.month &&
        e.start.day == day.day)
      e,
];

int minuteOf(DateTime t) => t.hour * 60 + t.minute;

void main() {
  group('a habit as stored', () {
    test('goes to JSON and back unchanged, keeping keys it does not know', () {
      final habit = PlannerHabit.fromJson({
        'id': 'gym',
        'title': 'Gym',
        'minutes': 60,
        'minMinutes': 30,
        'days': [5, 1, 3],
        'ideal': 18 * 60,
        'earliest': 6 * 60,
        'latest': 22 * 60,
        'hours': 'personal',
        'paused': true,
        'colour': 'green',
      })!;
      expect(habit.days, {1, 3, 5});
      expect(habit.minMinutes, 30);
      expect(habit.hoursId, personalHoursId);
      expect(habit.paused, isTrue);
      expect(habit.extra, {'colour': 'green'});
      expect(PlannerHabit.fromJson(habit.toJson())!.toJson(), habit.toJson());
      expect(habit.toJson()['days'], [1, 3, 5]);
    });

    test('that cannot be planned is left out, and odd values are kept in range', () {
      expect(PlannerHabit.fromJson({'id': 'x', 'minutes': 3, 'days': [1]}), isNull);
      expect(PlannerHabit.fromJson({'id': PlannerHabit.focusId, 'minutes': 30}), isNull);
      expect(
        PlannerHabit.fromJson({'id': 'x', 'minutes': 30, 'earliest': 600, 'latest': 600}),
        isNull,
      );
      final odd = PlannerHabit.fromJson({
        'id': 'x',
        'minutes': 90,
        'minMinutes': 120,
        'days': [0, 2, 9, 'mon'],
        'ideal': 23 * 60,
        'earliest': 8 * 60,
        'latest': 10 * 60,
        'hours': 'garden',
      })!;
      expect(odd.days, {2});
      expect(odd.minMinutes, isNull, reason: 'shortest must be shorter than the length');
      expect(odd.ideal, 8 * 60 + 30, reason: 'the ideal start leaves room to finish');
      expect(odd.hoursId, isNull);
    });

    test('settings from before habits read and write exactly as they did', () {
      final old = PlannerSettings(
        enabled: true,
        hours: PlannerSettings.defaultHours(DateTime.sunday),
        tasks: PlannerTasksChoice.all,
      ).toJson();
      final read = PlannerSettings.fromJson(old);
      expect(read.habits, isEmpty);
      expect(read.focusMinutesPerWeek, 0);
      expect(read.toJson(), old);
      expect(old.containsKey('habits'), isFalse);
      expect(old.containsKey('focusPerWeek'), isFalse);
      // The same signature as before, so blocks aren't all moved after the
      // update.
      expect(
        read.planSignature,
        jsonEncode([
          for (final key in const [
            'hours', 'tasks', 'defaultMinutes', 'minChunk', 'maxChunk',
            'breakAfterMeetings', 'maxMinutesPerDay', 'freeCalendars', 'allDayBusy',
          ])
            old[key],
        ]),
      );
    });

    test('habits and the focus goal are saved, and change the signature', () {
      final s = settings.copyWith(focusMinutesPerWeek: 600, focusTitle: 'Deep work');
      final read = PlannerSettings.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(read.habits.single.toJson(), lunch.toJson());
      expect(read.focusMinutesPerWeek, 600);
      expect(read.focusTitle, 'Deep work');
      expect(read.planSignature, isNot(settings.copyWith(habits: const []).planSignature));
      expect(
        read.planSignature,
        isNot(read.copyWith(habits: [lunch.copyWith(ideal: 13 * 60)]).planSignature),
      );
    });

    test('the same id twice keeps the first', () {
      final s = PlannerSettings.fromJson({
        ...settings.toJson(),
        'habits': [lunch.toJson(), {...lunch.toJson(), 'title': 'Second'}],
      });
      expect(s.habits.single.title, 'Lunch');
    });
  });

  group('focus time', () {
    test('splits the weekly goal over the work days, in work hours', () {
      final focus = focusHabitOf(settings.copyWith(focusMinutesPerWeek: 600))!;
      expect(focus.id, PlannerHabit.focusId);
      expect(focus.days, {1, 2, 3, 4, 5});
      expect(focus.minutes, 120);
      expect(focus.minMinutes, 60, reason: 'shortened to half rather than dropped');
      expect(focus.hoursId, workHoursId);
      expect(focus.ideal, 9 * 60, reason: 'as early in the day as there is room');
    });

    test('rounds up to 15 minutes, and is off with no goal', () {
      expect(focusHabitOf(settings.copyWith(focusMinutesPerWeek: 100))!.minutes, 30);
      expect(focusHabitOf(settings.copyWith(focusMinutesPerWeek: 100))!.minMinutes, isNull);
      expect(focusHabitOf(settings), isNull);
      expect(plannedHabitsOf(settings).map((h) => h.id), ['lunch']);
      expect(
        plannedHabitsOf(settings.copyWith(focusMinutesPerWeek: 300)).map((h) => h.id),
        ['lunch', PlannerHabit.focusId],
      );
      expect(
        plannedHabitsOf(settings.copyWith(habits: [lunch.copyWith(paused: true)])),
        isEmpty,
      );
    });
  });

  group('planning habits', () {
    test('lunch goes at its ideal time on a free day, with its own title and mark', () {
      final outcome = computePlan(
        now: sundayEvening,
        settings: settings,
        events: const [],
        calendars: calendars,
        tasks: const [],
      );
      final monday = blocksOf(outcome.save, 'lunch', mon(0)).single;
      expect(monday.title, 'Lunch');
      expect(monday.start, mon(12, 30));
      expect(monday.duration.inMinutes, 30);
      expect(monday.calendarId, plannerCalendarId);
      expect(monday.taskIds, isEmpty);
      final mark = PlanMark.of(monday)!;
      expect(mark.isHabit, isTrue);
      expect(mark.done, isFalse);
      // Every day, weekends too: lunch has no hours of its own.
      expect(blocksOf(outcome.save, 'lunch', DateTime(2026, 11, 28)), hasLength(1));
    });

    test('moves around a meeting inside its window, before tasks take the time', () {
      final events = [
        CalendarEvent(
          id: 'm',
          title: 'Meeting',
          start: mon(12),
          end: mon(13, 15),
          calendarId: 'default',
        ),
      ];
      final outcome = computePlan(
        now: sundayEvening,
        settings: settings,
        events: events,
        calendars: calendars,
        tasks: [
          PlannerTask(id: 't', title: 'Report', minutes: 8 * 60, createdAt: 't'),
        ],
      );
      final after = apply(events, outcome);
      final block = blocksOf(after, 'lunch', mon(0)).single;
      expect(minuteOf(block.start), greaterThanOrEqualTo(11 * 60 + 30));
      expect(minuteOf(block.end), lessThanOrEqualTo(14 * 60));
      expect(block.start.isBefore(mon(13, 15)) && mon(12).isBefore(block.end), isFalse);
      // The task's blocks keep clear of lunch.
      for (final t in blocksOf(after, 't', mon(0))) {
        expect(t.start.isBefore(block.end) && block.start.isBefore(t.end), isFalse,
            reason: 'task block at ${t.start} overlaps lunch at ${block.start}');
      }
    });

    test('is shortened when there is little room, and skipped when there is none', () {
      final squeezed = [
        CalendarEvent(id: 'a', title: 'a', start: mon(11, 30), end: mon(12, 45), calendarId: 'default'),
        CalendarEvent(id: 'b', title: 'b', start: mon(13), end: mon(14), calendarId: 'default'),
        CalendarEvent(id: 'c', title: 'c', start: tue(11), end: tue(15), calendarId: 'default'),
      ];
      final outcome = computePlan(
        now: sundayEvening,
        settings: settings.copyWith(breakAfterMeetings: 0),
        events: squeezed,
        calendars: calendars,
        tasks: const [],
      );
      final monday = blocksOf(outcome.save, 'lunch', mon(0)).single;
      expect(monday.duration.inMinutes, 15);
      expect(blocksOf(outcome.save, 'lunch', tue(0)), isEmpty);
      expect(outcome.result.skippedHabits, isNotEmpty);
    });

    test('a passed lunch counts as kept, and is not planned again that day', () {
      final events = [habitBlock('lunch:20261123', 'lunch', mon(12, 30), 30)];
      final outcome = computePlan(
        now: mon(15),
        settings: settings,
        events: events,
        calendars: calendars,
        tasks: const [],
      );
      final after = apply(events, outcome);
      final today = blocksOf(after, 'lunch', mon(0));
      expect(today, hasLength(1));
      expect(PlanMark.of(today.single)!.done, isTrue);
      expect(today.single.start, mon(12, 30), reason: 'a record of when it was');
      expect(blocksOf(after, 'lunch', tue(0)), hasLength(1));
    });

    test('a skipped lunch stays skipped, and frees the time for tasks', () {
      final events = [
        habitBlock('lunch:20261123', 'lunch', mon(12, 30), 30, done: true, skipped: true),
      ];
      final outcome = computePlan(
        now: mon(9),
        settings: settings,
        events: events,
        calendars: calendars,
        tasks: const [],
      );
      expect(outcome.save.where((e) => e.id == 'lunch:20261123'), isEmpty);
      expect(outcome.delete, isNot(contains('lunch:20261123')));
      final after = apply(events, outcome);
      expect(blocksOf(after, 'lunch', mon(0)), hasLength(1));
      expect(PlanMark.of(blocksOf(after, 'lunch', mon(0)).single)!.skipped, isTrue);
    });

    test('a deleted habit takes its coming times with it, and leaves the past ones', () {
      final events = [
        habitBlock('lunch:20261123', 'lunch', mon(12, 30), 30, done: true),
        habitBlock('lunch:20261124', 'lunch', tue(12, 30), 30),
      ];
      final outcome = computePlan(
        now: mon(15),
        settings: settings.copyWith(habits: const []),
        events: events,
        calendars: calendars,
        tasks: const [],
      );
      expect(outcome.delete, ['lunch:20261124']);
    });

    test('a renamed habit renames its coming blocks', () {
      final events = [habitBlock('lunch:20261124', 'lunch', tue(12, 30), 30)];
      final outcome = computePlan(
        now: mon(15),
        settings: settings.copyWith(habits: [lunch.copyWith(title: 'Break')]),
        events: events,
        calendars: calendars,
        tasks: const [],
      );
      expect(outcome.save.firstWhere((e) => e.id == 'lunch:20261124').title, 'Break');
    });

    test('focus time is planned in work hours on work days only', () {
      final outcome = computePlan(
        now: sundayEvening,
        settings: settings.copyWith(habits: const [], focusMinutesPerWeek: 600, focusTitle: 'Focus time'),
        events: const [],
        calendars: calendars,
        tasks: const [],
      );
      final monday = blocksOf(outcome.save, PlannerHabit.focusId, mon(0)).single;
      expect(monday.title, 'Focus time');
      expect(monday.start, mon(9));
      expect(monday.duration.inMinutes, 120);
      expect(blocksOf(outcome.save, PlannerHabit.focusId, DateTime(2026, 11, 28)), isEmpty);
    });
  });

  group('the week in numbers', () {
    test('counts tasks, focus time and habits apart, and the last seven days', () {
      final today = mon(0);
      final numbers = plannerWeekNumbers([
        taskBlock('t1', 't', mon(10), 60),
        taskBlock('t2', 't', tue(10), 90),
        taskBlock('old', 't', DateTime(2026, 11, 20, 10), 45, done: true),
        taskBlock('missed', 't', DateTime(2026, 11, 19, 10), 60),
        habitBlock('f1', PlannerHabit.focusId, mon(9), 120, title: 'Focus time'),
        habitBlock('l1', 'lunch', mon(12, 30), 30),
        habitBlock('l2', 'lunch', tue(12, 30), 30, done: true, skipped: true),
        habitBlock('l3', 'lunch', DateTime(2026, 11, 21, 12, 30), 30, done: true),
        habitBlock('l4', 'lunch', DateTime(2026, 11, 20, 12, 30), 30, done: true, skipped: true),
        habitBlock('l5', 'lunch', DateTime(2026, 11, 19, 12, 30), 30, done: true),
        // Outside both weeks.
        habitBlock('l6', 'lunch', DateTime(2026, 11, 10, 12, 30), 30, done: true),
        taskBlock('far', 't', DateTime(2026, 12, 10, 10), 60),
      ], today);
      expect(numbers.taskMinutesByDay[mon(0)], 60);
      expect(numbers.taskMinutesByDay[tue(0)], 90);
      expect(numbers.taskMinutesByDay.values.fold(0, (a, b) => a + b), 150);
      expect(numbers.focusMinutes, 120);
      expect(numbers.habitBlocks, 1, reason: 'the skipped one is not counted');
      expect(numbers.doneTaskMinutes, 45);
      expect(numbers.habitsKept, 2);
      expect(numbers.habitsSkipped, 1);
    });
  });
}
