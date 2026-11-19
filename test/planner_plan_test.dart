import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/data/find_a_time.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/planner/planner_plan.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

/// Sunday 22 November 2026, 20:00: the evening before a work week.
final sundayEvening = DateTime(2026, 11, 22, 20);
DateTime mon(int h, [int m = 0]) => DateTime(2026, 11, 23, h, m);
DateTime tue(int h, [int m = 0]) => DateTime(2026, 11, 24, h, m);
DateTime wed(int h, [int m = 0]) => DateTime(2026, 11, 25, h, m);

/// Work Monday to Friday 9:00 to 17:00, the Planner on, every task planned.
final settings = PlannerSettings(
  enabled: true,
  hours: PlannerSettings.defaultHours(DateTime.monday),
  tasks: PlannerTasksChoice.all,
);

const calendars = [
  ZtCalendarInfo.personal,
  ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
];

CalendarEvent meeting(String id, DateTime start, DateTime end, {String calendarId = 'default'}) =>
    CalendarEvent(id: id, title: id, start: start, end: end, calendarId: calendarId);

PlannerTask task(
  String id, {
  int? minutes,
  DateTime? due,
  bool dueHasTime = false,
  PlanPriority priority = PlanPriority.medium,
  bool? auto,
  bool completed = false,
  bool repeats = false,
  String? dueRaw,
  String? title,
}) => PlannerTask(
  id: id,
  title: title ?? id,
  minutes: minutes,
  due: due,
  dueHasTime: dueHasTime,
  priority: priority,
  auto: auto,
  completed: completed,
  repeats: repeats,
  dueRaw: dueRaw ?? due?.toIso8601String(),
  createdAt: id,
);

/// The stored events once [outcome] is saved.
List<CalendarEvent> apply(List<CalendarEvent> events, PlannerOutcome outcome) => [
  for (final e in events)
    if (!outcome.delete.contains(e.id) && !outcome.save.any((s) => s.id == e.id)) e,
  ...outcome.save,
];

/// Plans, checks the plan against the rules every plan must keep, and
/// returns the outcome.
PlannerOutcome planChecked({
  required DateTime now,
  required List<CalendarEvent> events,
  required List<PlannerTask> tasks,
  PlannerSettings? with_,
  List<ZtCalendarInfo> cals = calendars,
  bool rebuild = false,
}) {
  final s = with_ ?? settings;
  final outcome = computePlan(
    now: now,
    settings: s,
    events: events,
    calendars: cals,
    tasks: tasks,
    rebuild: rebuild,
  );
  final after = apply(events, outcome);
  final busy = [
    for (final e in after)
      if (PlanMark.of(e) == null && !e.allDay) e,
  ];
  final blocks = [
    for (final e in after)
      if (PlanMark.of(e) != null) e,
  ];
  for (final b in outcome.save) {
    final mark = PlanMark.of(b)!;
    expect(b.calendarId, plannerCalendarId);
    expect(b.taskIds, [mark.itemId], reason: 'a block links to its task');
    if (mark.done) continue;
    expect(b.start.isAfter(now), isTrue, reason: '${b.id} starts in the past');
    for (final e in busy) {
      expect(
        b.start.isBefore(e.end) && e.start.isBefore(b.end),
        isFalse,
        reason: '${b.id} at ${b.start} overlaps ${e.id}',
      );
    }
    final hours = s.rangesOn(workHoursId, b.start.weekday);
    final from = b.start.hour * 60 + b.start.minute;
    final to = from + b.duration.inMinutes;
    expect(
      hours.any((r) => r.$1 <= from && to <= r.$2),
      isTrue,
      reason: '${b.id} at ${b.start} is outside the work hours',
    );
  }
  for (final a in blocks) {
    for (final b in blocks) {
      if (a.id.compareTo(b.id) >= 0) continue;
      expect(
        a.start.isBefore(b.end) && b.start.isBefore(a.end),
        isFalse,
        reason: '${a.id} overlaps ${b.id}',
      );
    }
  }
  return outcome;
}

int plannedMinutes(List<CalendarEvent> events, String taskId) => [
  for (final e in events)
    if (PlanMark.of(e)?.itemId == taskId) e.duration.inMinutes,
].fold(0, (a, b) => a + b);

void main() {
  group('the plan field of a block', () {
    test('is read from events of the Planned calendar only', () {
      final block = CalendarEvent(
        id: 't1:1',
        title: 'Report',
        start: mon(9),
        end: mon(10),
        calendarId: plannerCalendarId,
        extra: const {
          'plan': {'type': 'task', 'taskId': 't1', 'locked': true, 'done': false, 'newer': 7},
        },
      );
      final mark = PlanMark.of(block)!;
      expect(mark.kind, PlanBlockKind.task);
      expect(mark.itemId, 't1');
      expect(mark.locked, isTrue);
      expect(mark.done, isFalse);
      // A field a newer version wrote is written back.
      expect(mark.copyWith(done: true).toJson()['newer'], 7);
      expect(PlanMark.of(block.copyWith(calendarId: 'default')), isNull);
      expect(PlanMark.of(meeting('m', mon(9), mon(10), calendarId: plannerCalendarId)), isNull);
    });

    test('survives being stored as an event', () {
      final outcome = planChecked(
        now: sundayEvening,
        events: const [],
        tasks: [task('report', minutes: 60)],
      );
      final block = outcome.save.single;
      final again = CalendarEvent.fromJson(block.id, block.toJson(), null)!;
      expect(PlanMark.of(again)!.itemId, 'report');
      expect(again.start, block.start);
      expect(again.taskIds, ['report']);
    });
  });

  group('the Planner settings', () {
    test('default hours follow the week: Sunday to Thursday or Monday to Friday', () {
      final il = PlannerSettings.defaultHours(DateTime.sunday);
      expect(il[workHoursId]!.keys.toSet(), {7, 1, 2, 3, 4});
      expect(il[workHoursId]![DateTime.sunday], [(540, 1020)]);
      final eu = PlannerSettings.defaultHours(DateTime.monday);
      expect(eu[workHoursId]!.keys.toSet(), {1, 2, 3, 4, 5});
      // Personal hours cover every day: evenings on work days.
      expect(eu[personalHoursId]!.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});
      expect(eu[personalHoursId]![DateTime.monday], [(1080, 1260)]);
      expect(eu[personalHoursId]![DateTime.saturday], [(600, 1080)]);
    });

    test('are stored and read back the same', () {
      final s = settings.copyWith(
        defaultMinutes: 45,
        minChunk: 15,
        maxChunk: 90,
        breakAfterMeetings: 5,
        maxMinutesPerDay: 240,
        freeCalendarIds: {'b', 'a'},
        allDayBusy: true,
        pastBlocks: PastBlocks.countAsDone,
        remindAtStart: false,
      );
      final back = PlannerSettings.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.enabled, isTrue);
      expect(back.tasks, PlannerTasksChoice.all);
      expect(back.rangesOn(workHoursId, DateTime.monday), [(540, 1020)]);
      expect(back.rangesOn(workHoursId, DateTime.saturday), isEmpty);
      expect(back.freeCalendarIds, {'a', 'b'});
      expect(back.pastBlocks, PastBlocks.countAsDone);
      expect(back.weeklyMinutes(workHoursId), 5 * 8 * 60);
    });

    test('are off and safe when nothing or nonsense is stored', () {
      final empty = PlannerSettings.fromJson(const {});
      expect(empty.enabled, isFalse);
      expect(empty.tasks, PlannerTasksChoice.switchedOn);
      expect(empty.defaultMinutes, 30);
      expect(empty.remindAtStart, isTrue);
      final odd = PlannerSettings.fromJson(const {
        'enabled': 'yes',
        'hours': {
          'work': {
            '1': [
              [600, 540],
              [-5, 30],
              [540, 720],
            ],
            '9': [
              [540, 600],
            ],
          },
        },
        'minChunk': 120,
        'maxChunk': 30,
        'later': {'a': 1},
      });
      expect(odd.enabled, isFalse);
      expect(odd.hours[workHoursId], {
        1: [(540, 720)],
      });
      expect(odd.maxChunk, greaterThanOrEqualTo(odd.minChunk));
      expect(odd.toJson()['later'], {'a': 1});
    });
  });

  group('a task as the Planner reads it', () {
    final json = <String, Object?>{
      'title': ' Write report ',
      'priority': 'high',
      'dueDate': '2026-11-26T00:00:00.000',
      'startDate': '2026-11-23T00:00:00.000',
      'isCompleted': false,
      'isArchived': false,
      'deletedAt': null,
      'recurrence': null,
      'createdAt': '2026-11-01T10:00:00.000',
      'subTasks': <Object?>[],
      'starred': true,
      'planMinutes': 180,
      'planAuto': true,
      'planHours': 'personal',
    };

    test('has its length, dates, priority and hours', () {
      final t = PlannerTask.fromItem('t1', json)!;
      expect(t.title, 'Write report');
      expect(t.minutes, 180);
      expect(t.priority, PlanPriority.high);
      expect(t.auto, isTrue);
      expect(t.hoursId, personalHoursId);
      expect(t.notBefore, DateTime(2026, 11, 23));
      // A due date without a time means the end of that day.
      expect(t.dueHasTime, isFalse);
      expect(t.dueBy, DateTime(2026, 11, 27));
      final timed = PlannerTask.fromItem('t1', {...json, 'dueDate': '2026-11-26T15:30:00.000'})!;
      expect(timed.dueBy, DateTime(2026, 11, 26, 15, 30));
    });

    test('is read with no due date and no plan fields too', () {
      final t = PlannerTask.fromItem('t2', const {'title': 'Someday', 'isCompleted': false})!;
      expect(t.due, isNull);
      expect(t.minutes, isNull);
      expect(t.auto, isNull);
      expect(t.hoursId, workHoursId);
      expect(t.priority, PlanPriority.medium);
    });

    test('lists, archived and deleted tasks are not tasks to plan', () {
      expect(PlannerTask.fromItem('l', {...json, 'kind': 'list'}), isNull);
      expect(PlannerTask.fromItem('a', {...json, 'isArchived': true}), isNull);
      expect(PlannerTask.fromItem('d', {...json, 'deletedAt': '2026-11-02T00:00:00.000'}), isNull);
      expect(PlannerTask.fromItem('n', null), isNull);
    });

    test('only switched-on tasks are planned, or all but the ones switched off', () {
      final never = task('a');
      final on = task('b', auto: true);
      final off = task('c', auto: false);
      final done = task('d', auto: true, completed: true);
      const only = PlannerTasksChoice.switchedOn;
      const all = PlannerTasksChoice.all;
      expect([never, on, off, done].map((t) => t.plannedUnder(only)), [false, true, false, false]);
      expect([never, on, off, done].map((t) => t.plannedUnder(all)), [true, true, false, false]);
    });

    test('changing its plan fields keeps every other field as stored', () {
      final now = DateTime(2026, 11, 18, 12);
      final out = PlannerTask.withPlanFields(json, {'planMinutes': 90, 'planHours': null}, now);
      expect(out['planMinutes'], 90);
      expect(out.containsKey('planHours'), isFalse);
      expect(out['updatedAt'], now.toIso8601String());
      for (final key in json.keys) {
        if (key == 'planMinutes' || key == 'planHours') continue;
        expect(out[key], json[key], reason: key);
      }
      // Calendar must never change a task's own fields this way.
      expect(
        () => PlannerTask.withPlanFields(json, {'title': 'x'}, now),
        throwsArgumentError,
      );
    });
  });

  group('planning', () {
    test('the example from the design: three tasks around Monday\'s meetings', () {
      final events = [meeting('meetings', mon(10), mon(12))];
      final tasks = [
        task('tax', minutes: 180, due: DateTime(2026, 11, 26), priority: PlanPriority.high),
        task('bank', minutes: 15, due: DateTime(2026, 11, 24)),
        task('contract', minutes: 60),
      ];
      final outcome = planChecked(now: sundayEvening, events: events, tasks: tasks);
      final after = apply(events, outcome);
      expect(outcome.result.risks, isEmpty);
      expect(outcome.delete, isEmpty);
      expect(plannedMinutes(after, 'tax'), 180);
      expect(plannedMinutes(after, 'bank'), 15);
      expect(plannedMinutes(after, 'contract'), 60);
      // The most important task gets the first free time: Monday 9:00.
      final first = outcome.save.reduce((a, b) => a.start.isBefore(b.start) ? a : b);
      expect(first.start, mon(9));
      expect(PlanMark.of(first)!.itemId, 'tax');
      // The break after the meeting: nothing starts before 12:10.
      for (final b in outcome.save) {
        expect(
          b.start.isBefore(mon(12, 10)) && b.end.isAfter(mon(12)),
          isFalse,
          reason: '${b.id} starts in the break after the meeting',
        );
      }
      // Everything is finished before Thursday.
      for (final b in outcome.save.where((b) => PlanMark.of(b)!.itemId == 'tax')) {
        expect(b.end.isAfter(DateTime(2026, 11, 27)), isFalse);
      }
      // Blocks carry the task's title and a start reminder.
      expect(outcome.save.map((b) => b.title).toSet(), {'tax', 'bank', 'contract'});
      expect(outcome.save.every((b) => b.reminders.length == 1 && b.reminders.first == 0), isTrue);
    });

    test('planning again from the saved blocks changes nothing', () {
      final events = [meeting('meetings', mon(10), mon(12))];
      final tasks = [
        task('tax', minutes: 180, due: DateTime(2026, 11, 26), priority: PlanPriority.high),
        task('bank', minutes: 15, due: DateTime(2026, 11, 24)),
        task('contract', minutes: 60),
      ];
      final first = planChecked(now: sundayEvening, events: events, tasks: tasks);
      final stored = apply(events, first);
      final again = planChecked(now: sundayEvening, events: stored, tasks: tasks);
      expect(again.changesNothing, isTrue, reason: '${again.save} ${again.delete}');
      // Also an hour later, and after the blocks went through storage.
      final reread = [
        for (final e in stored) CalendarEvent.fromJson(e.id, e.toJson(), null)!,
      ];
      final later = planChecked(
        now: sundayEvening.add(const Duration(hours: 1)),
        events: reread,
        tasks: tasks,
      );
      expect(later.changesNothing, isTrue, reason: '${later.save} ${later.delete}');
    });

    test('a new meeting on a block moves the block, keeping its id', () {
      final tasks = [task('report', minutes: 120)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: tasks);
      final block = first.save.single;
      expect(block.start, mon(9));
      expect(block.end, mon(11));
      final stored = [...first.save, meeting('new', mon(9), mon(10))];
      final second = planChecked(now: sundayEvening, events: stored, tasks: tasks);
      expect(second.delete, isEmpty);
      expect(second.save.single.id, block.id);
      // After the meeting and its 10 minute break, on the quarter hour.
      expect(second.save.single.start, mon(10, 15));
      expect(second.save.single.end, mon(12, 15));
    });

    test('only tasks that are switched on are planned, unless all are', () {
      final tasks = [task('a', minutes: 60), task('b', minutes: 60, auto: true), task('c', minutes: 60, auto: false)];
      final only = planChecked(
        now: sundayEvening,
        events: const [],
        tasks: tasks,
        with_: settings.copyWith(tasks: PlannerTasksChoice.switchedOn),
      );
      expect(only.save.map((b) => PlanMark.of(b)!.itemId).toSet(), {'b'});
      final all = planChecked(now: sundayEvening, events: const [], tasks: tasks);
      expect(all.save.map((b) => PlanMark.of(b)!.itemId).toSet(), {'a', 'b'});
    });

    test('a task with no length gets the usual length', () {
      final outcome = planChecked(
        now: sundayEvening,
        events: const [],
        tasks: [task('quick')],
        with_: settings.copyWith(defaultMinutes: 45),
      );
      expect(outcome.save.single.duration.inMinutes, 45);
    });

    test('a finished task loses its blocks; a renamed one is renamed in place', () {
      final tasks = [task('a', minutes: 60), task('b', minutes: 60)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: tasks);
      final stored = apply(const [], first);
      final second = planChecked(
        now: sundayEvening,
        events: stored,
        tasks: [task('a', minutes: 60, completed: true), task('b', minutes: 60, title: 'B, renamed')],
      );
      expect(second.delete, [stored.firstWhere((e) => PlanMark.of(e)!.itemId == 'a').id]);
      final renamed = second.save.single;
      final before = stored.firstWhere((e) => e.id == renamed.id);
      expect(renamed.title, 'B, renamed');
      // "b" may move up into the freed time, but it keeps its id and length.
      expect(renamed.duration, before.duration);
    });

    test('hidden calendars, calendars marked free and all-day events are not busy', () {
      final cals = [
        ...calendars,
        const ZtCalendarInfo(id: 'hidden', name: 'Hidden', color: 1, hidden: true),
        const ZtCalendarInfo(id: 'kids', name: 'Kids', color: 2),
      ];
      final events = [
        meeting('h', mon(9), mon(12), calendarId: 'hidden'),
        meeting('k', mon(9), mon(12), calendarId: 'kids'),
        CalendarEvent(
          id: 'holiday',
          title: 'Holiday',
          start: DateTime(2026, 11, 23),
          end: DateTime(2026, 11, 24),
          allDay: true,
        ),
      ];
      final tasks = [task('report', minutes: 60)];
      // "Kids" counts: the block waits until after it (and the break).
      final counted = computePlan(
        now: sundayEvening, settings: settings, events: events, calendars: cals, tasks: tasks);
      expect(counted.save.single.start, mon(12, 15));
      // Marked free: the block goes to Monday 9:00.
      final free = computePlan(
        now: sundayEvening,
        settings: settings.copyWith(freeCalendarIds: {'kids'}),
        events: events,
        calendars: cals,
        tasks: tasks,
      );
      expect(free.save.single.start, mon(9));
      // All-day events busy: Monday is out, so Tuesday 9:00.
      final allDay = computePlan(
        now: sundayEvening,
        settings: settings.copyWith(freeCalendarIds: {'kids'}, allDayBusy: true),
        events: events,
        calendars: cals,
        tasks: tasks,
      );
      expect(allDay.save.single.start, tue(9));
    });

    test('a task that cannot make its due date is reported', () {
      final outcome = planChecked(
        now: sundayEvening,
        events: const [],
        tasks: [task('huge', minutes: 600, due: DateTime(2026, 11, 23))],
      );
      final risk = outcome.result.risks.single;
      expect(risk.taskId, 'huge');
      expect(risk.minutesLate, greaterThan(0));
    });

    test('without the start reminder, blocks have none, and old ones lose it', () {
      final tasks = [task('a', minutes: 60)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: tasks);
      expect(first.save.single.reminders, [0]);
      final quiet = planChecked(
        now: sundayEvening,
        events: first.save,
        tasks: tasks,
        with_: settings.copyWith(remindAtStart: false),
      );
      expect(quiet.save.single.reminders, isEmpty);
      expect(quiet.save.single.start, first.save.single.start);
    });

    test('a passed block waits that day and is planned again the next', () {
      final tasks = [task('a', minutes: 60)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: tasks);
      final stored = apply(const [], first);
      expect(stored.single.start, mon(9));
      // Monday noon: the block has passed without an answer. It stays.
      final noon = planChecked(now: mon(12), events: stored, tasks: tasks);
      expect(noon.changesNothing, isTrue);
      // Tuesday morning: its time goes back to the task.
      final next = planChecked(now: tue(8), events: stored, tasks: tasks);
      final after = apply(stored, next);
      expect(after.single.start, tue(9));
      expect(plannedMinutes(after, 'a'), 60);
    });

    test('with "count as done", a passed block is marked done and kept', () {
      final s = settings.copyWith(pastBlocks: PastBlocks.countAsDone);
      final tasks = [task('a', minutes: 120)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: tasks, with_: s);
      final stored = apply(const [], first);
      final noon = planChecked(now: mon(12), events: stored, tasks: tasks, with_: s);
      final done = noon.save.single;
      expect(PlanMark.of(done)!.done, isTrue);
      expect(done.start, mon(9));
      // Nothing more is planned: the two hours are done.
      final after = apply(stored, noon);
      expect(after, hasLength(1));
      final again = planChecked(now: mon(13), events: after, tasks: tasks, with_: s);
      expect(again.changesNothing, isTrue);
    });

    test('a repeating task starts over when ZT Tasks rolls it to its next date', () {
      final s = settings.copyWith(pastBlocks: PastBlocks.countAsDone);
      final week1 = [task('gym', minutes: 60, due: DateTime(2026, 11, 24), repeats: true)];
      final first = planChecked(now: sundayEvening, events: const [], tasks: week1, with_: s);
      final stored = apply(const [], first);
      expect(PlanMark.of(stored.single)!.occurrence, week1.single.dueRaw);
      final afterDone = apply(stored, planChecked(now: mon(12), events: stored, tasks: week1, with_: s));
      expect(PlanMark.of(afterDone.single)!.done, isTrue);
      // Ticked off in ZT Tasks: the task moves a week on. Last week's done
      // block stays as history and the new date gets its own hour.
      final week2 = [task('gym', minutes: 60, due: DateTime(2026, 12, 1), repeats: true)];
      final next = planChecked(now: mon(13), events: afterDone, tasks: week2, with_: s);
      final after = apply(afterDone, next);
      expect(after, hasLength(2));
      expect(after.map((e) => e.id).toSet(), hasLength(2), reason: 'ids are not reused');
      final fresh = after.firstWhere((e) => !PlanMark.of(e)!.done);
      expect(fresh.duration.inMinutes, 60);
      expect(PlanMark.of(fresh)!.occurrence, week2.single.dueRaw);
      expect(PlanMark.of(after.firstWhere((e) => PlanMark.of(e)!.done))!.occurrence,
          week1.single.dueRaw);
    });

    test('a rebuild places blocks afresh, as early as they fit', () {
      final tasks = [task('a', minutes: 60)];
      final first = planChecked(
        now: sundayEvening,
        events: [meeting('m', mon(9), mon(12))],
        tasks: tasks,
      );
      expect(first.save.single.start, mon(12, 15));
      // The meeting is cancelled. The block stays (calm) until a rebuild.
      final calm = planChecked(now: sundayEvening, events: first.save, tasks: tasks);
      expect(calm.changesNothing, isTrue);
      final tidy = planChecked(now: sundayEvening, events: first.save, tasks: tasks, rebuild: true);
      expect(tidy.save.single.id, first.save.single.id);
      expect(tidy.save.single.start, mon(9));
    });
  });

  group('blocks on the calendar', () {
    final l10n = lookupAppL10n(const Locale('en'));
    final he = lookupAppL10n(const Locale('he'));

    test('a task in several blocks shows which block each is', () {
      final outcome = planChecked(
        now: sundayEvening,
        events: const [],
        tasks: [task('tax', minutes: 240, title: 'Tax papers'), task('bank', minutes: 15, title: 'Call the bank')],
      );
      final entries = buildEntries(
        range: DateRange(DateTime(2026, 11, 23), DateTime(2026, 11, 28)),
        events: outcome.save,
        calendars: calendars,
        l10n: l10n,
      );
      final titles = entries.map((e) => e.title).toList();
      expect(titles, containsAll(['Tax papers (1 of 2)', 'Tax papers (2 of 2)', 'Call the bank']));
      expect(entries.every((e) => e.plan != null), isTrue);
      expect(entries.every((e) => e.color == plannerColor), isTrue);
      final hebrew = buildEntries(
        range: DateRange(DateTime(2026, 11, 23), DateTime(2026, 11, 28)),
        events: outcome.save,
        calendars: calendars,
        l10n: he,
      );
      expect(hebrew.map((e) => e.title), contains('Tax papers (1 מתוך 2)'));
    });

    test('hiding the Planned calendar hides the blocks', () {
      final outcome = planChecked(
        now: sundayEvening, events: const [], tasks: [task('a', minutes: 60)]);
      final entries = buildEntries(
        range: DateRange(DateTime(2026, 11, 23), DateTime(2026, 11, 28)),
        events: outcome.save,
        calendars: [
          ZtCalendarInfo.personal,
          const ZtCalendarInfo(
            id: plannerCalendarId, name: 'Planned', color: plannerColor, hidden: true),
        ],
        l10n: l10n,
      );
      expect(entries, isEmpty);
    });

    test('a block that can still move is not a busy time for others', () {
      final outcome = planChecked(
        now: sundayEvening, events: const [], tasks: [task('a', minutes: 60)]);
      final block = outcome.save.single;
      final locked = block.copyWith(
        extra: {'plan': PlanMark.of(block)!.copyWith(locked: true).toJson()},
      );
      final events = [meeting('m', mon(14), mon(15)), block];
      expect(
        busyBlocks(events: events, calendars: calendars, from: DateTime(2026, 11, 23)),
        [(mon(14), mon(15))],
      );
      expect(
        busyBlocks(
          events: [meeting('m', mon(14), mon(15)), locked],
          calendars: calendars,
          from: DateTime(2026, 11, 23),
        ),
        [(mon(9), mon(10)), (mon(14), mon(15))],
      );
    });
  });
}
