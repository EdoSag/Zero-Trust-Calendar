import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/entries.dart';
import 'package:zerotrust_calendar/data/event_done.dart';
import 'package:zerotrust_calendar/data/find_a_time.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_answers.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zerotrust_calendar/reminders/reminders.dart';

CalendarEvent block(String id, DateTime start, {bool done = false, List<int> reminders = const [0]}) =>
    CalendarEvent(
      id: id,
      title: 'Write report',
      start: start,
      end: start.add(const Duration(hours: 1)),
      calendarId: plannerCalendarId,
      taskIds: const ['a'],
      reminders: reminders,
      extra: {
        'plan': {'type': 'task', 'taskId': 'a', 'locked': false, 'done': done},
      },
    );

void main() {
  final now = DateTime(2026, 11, 23, 8);
  final at10 = DateTime(2026, 11, 23, 10);

  List<ScheduledReminder> reminders(
    List<CalendarEvent> events, {
    bool ask = true,
    Set<String> hidden = const {},
  }) => remindersFor(
    events,
    now: now,
    bodyFor: (e, s) => 'body',
    hiddenCalendars: hidden,
    askAtBlockEnd: ask,
    blockEndTitle: (b) => 'Finished ${b.title}?',
    blockEndBody: (b) => '1 hour',
  );

  group('A habit skipped for the day', () {
    CalendarEvent lunch({required bool skipped}) => CalendarEvent(
      id: 'lunch:20261123',
      title: 'Lunch',
      start: DateTime(2026, 11, 23, 12),
      end: DateTime(2026, 11, 23, 13),
      calendarId: plannerCalendarId,
      reminders: const [0],
      extra: {
        'plan': {
          'type': 'habit',
          'habitId': 'lunch',
          'locked': false,
          'done': skipped,
          if (skipped) 'skipped': true,
        },
      },
    );

    test('does not remind, and reminds again when kept after all', () {
      expect(reminders([lunch(skipped: true)]), isEmpty);
      expect(reminders([lunch(skipped: false)]).single.at, DateTime(2026, 11, 23, 12));
    });

    test('leaves its time free for Find a time and shared free/busy', () {
      List<(DateTime, DateTime)> busy(CalendarEvent e) => busyBlocks(
        events: [e],
        calendars: const [
          ZtCalendarInfo(id: plannerCalendarId, name: 'Planned', color: plannerColor),
        ],
        from: now,
      );
      expect(busy(lunch(skipped: true)), isEmpty);
      // A habit kept (done, not skipped) still counts, like any done block.
      final kept = lunch(skipped: false).copyWith(
        extra: {
          'plan': {'type': 'habit', 'habitId': 'lunch', 'locked': false, 'done': true},
        },
      );
      expect(busy(kept), hasLength(1));
    });
  });

  group('The question when a block ends', () {
    test('is asked at the end of a block that is not done, with its own buttons', () {
      final list = reminders([block('a:1', at10)]);
      expect(list, hasLength(2));
      // The reminder at the start, as for any event.
      expect(list.first.at, at10);
      expect(list.first.planEnd, isFalse);
      expect(list.first.actions, [ReminderAction.snooze]);
      // The question at the end.
      final end = list.last;
      expect(end.at, DateTime(2026, 11, 23, 11));
      expect(end.planEnd, isTrue);
      expect(end.title, 'Finished Write report?');
      expect(end.body, '1 hour');
      expect(end.actions, ['plan-done', 'plan-more', 'plan-skip']);
      expect(end.notificationId, isNot(list.first.notificationId));
      // Its buttons work without opening the app (so, while locked).
      for (final a in end.actions) {
        expect(ReminderAction.inBackground(a), isTrue, reason: a);
        expect(ReminderAction.labels[a], isNotEmpty);
      }
      expect(ReminderAction.inBackground(ReminderAction.map), isFalse);
    });

    test('is asked even when the block has no reminder at its start', () {
      final list = reminders([block('a:1', at10, reminders: const [])]);
      expect(list.single.planEnd, isTrue);
    });

    test('is not asked for done blocks, other events, hidden calendars, '
        'blocks that ended, or when switched off', () {
      final meeting = CalendarEvent(
        id: 'm',
        title: 'Meeting',
        start: at10,
        end: at10.add(const Duration(hours: 1)),
      );
      expect(reminders([block('a:1', at10, done: true)]).where((r) => r.planEnd), isEmpty);
      expect(reminders([meeting]), isEmpty);
      expect(reminders([block('a:1', at10)], hidden: {plannerCalendarId}), isEmpty);
      expect(
        reminders([block('a:1', DateTime(2026, 11, 23, 6))]).where((r) => r.planEnd),
        isEmpty,
      );
      expect(reminders([block('a:1', at10)], ask: false).where((r) => r.planEnd), isEmpty);
    });

    test('is not asked while the block is being timed, and is asked again '
        'for a timer left running too long to count', () {
      // "Start now" at 7:40: the block is 7:40 to 8:40, and it is 8:00.
      CalendarEvent timed(DateTime started) {
        final b = block('a:1', started, reminders: const []);
        final mark = PlanMark.of(b)!.copyWith(locked: true, started: started);
        return b.copyWith(extra: {...b.extra, 'plan': mark.toJson()});
      }

      final running = timed(DateTime(2026, 11, 23, 7, 40));
      expect(PlanMark.of(running)!.runningAt(now), isTrue);
      expect(reminders([running]), isEmpty);
      // The same block with no timer is asked about at 8:40.
      expect(
        reminders([block('a:1', DateTime(2026, 11, 23, 7, 40), reminders: const [])]).single.at,
        DateTime(2026, 11, 23, 8, 40),
      );
      // Started 13 hours ago and moved since: no longer a timer.
      final stale = timed(DateTime(2026, 11, 22, 19)).copyWith(
        start: at10,
        end: at10.add(const Duration(hours: 1)),
      );
      expect(PlanMark.of(stale)!.runningAt(now), isFalse);
      expect(reminders([stale]).single.planEnd, isTrue);
    });

    test('a button press becomes an answer for that block', () {
      final end = reminders([block('a:1', at10)]).last;
      PlanAnswer? press(String? action) => planAnswerOf(
        NotificationResponse(
          notificationResponseType: action == null
              ? NotificationResponseType.selectedNotification
              : NotificationResponseType.selectedNotificationAction,
          actionId: action,
          payload: end.payload,
        ),
      );
      expect(press('plan-done'), const PlanAnswer('a:1', PlanAnswerKind.done));
      expect(press('plan-more'), const PlanAnswer('a:1', PlanAnswerKind.more));
      expect(press('plan-skip'), const PlanAnswer('a:1', PlanAnswerKind.skip));
      // A tap on the notification itself, and other buttons, are not answers.
      expect(press(null), isNull);
      expect(press(ReminderAction.snooze), isNull);
      // The payload still opens the block on a tap.
      final payload = ReminderPayload.parse(end.payload)!;
      expect(payload.eventId, 'a:1');
      expect(payload.actions, ReminderAction.planEndActions);
    });
  });

  group('Answers kept on the phone', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('planner-answers'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('are read back in order and removed', () async {
      expect(await takePlanAnswers(dir), isEmpty);
      await appendPlanAnswer(dir, const PlanAnswer('a:1', PlanAnswerKind.done));
      await appendPlanAnswer(dir, const PlanAnswer('b:2', PlanAnswerKind.skip));
      expect(await takePlanAnswers(dir), const [
        PlanAnswer('a:1', PlanAnswerKind.done),
        PlanAnswer('b:2', PlanAnswerKind.skip),
      ]);
      expect(await takePlanAnswers(dir), isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('ones that could not be applied go back in front of newer ones', () async {
      await appendPlanAnswer(dir, const PlanAnswer('a:1', PlanAnswerKind.done));
      final taken = await takePlanAnswers(dir);
      // Another button is pressed before the first could be saved.
      await appendPlanAnswer(dir, const PlanAnswer('b:1', PlanAnswerKind.skip));
      await putBackPlanAnswers(dir, taken);
      await putBackPlanAnswers(dir, const []);
      expect(await takePlanAnswers(dir), const [
        PlanAnswer('a:1', PlanAnswerKind.done),
        PlanAnswer('b:1', PlanAnswerKind.skip),
      ]);
      expect(dir.listSync(), isEmpty);
    });

    test('hold only the block id and the button, no title or time', () async {
      await appendPlanAnswer(dir, const PlanAnswer('a:1', PlanAnswerKind.more));
      final text = File('${dir.path}/planner_answers.jsonl').readAsStringSync();
      expect(text, '{"b":"a:1","a":"more"}\n');
    });

    test('survive a broken line and a read that was cut short', () async {
      File('${dir.path}/planner_answers.jsonl.taking')
          .writeAsStringSync('{"b":"old:1","a":"done"}\n');
      File('${dir.path}/planner_answers.jsonl').writeAsStringSync(
        '{"b":"a:1","a":"done"}\nnot json\n{"b":"x","a":"dance"}\n\n{"b":"b:1","a":"skip"}\n',
      );
      expect(await takePlanAnswers(dir), const [
        PlanAnswer('old:1', PlanAnswerKind.done),
        PlanAnswer('a:1', PlanAnswerKind.done),
        PlanAnswer('b:1', PlanAnswerKind.skip),
      ]);
      expect(dir.listSync(), isEmpty);
    });
  });

  group('Mark as done on ordinary events', () {
    final lunch = CalendarEvent(
      id: 'lunch',
      title: 'Lunch',
      start: at10,
      end: at10.add(const Duration(hours: 1)),
      extra: const {'colorNote': 'kept'},
    );
    final standup = CalendarEvent(
      id: 'standup',
      title: 'Stand-up',
      start: at10,
      end: at10.add(const Duration(minutes: 30)),
      rrule: 'FREQ=DAILY',
    );

    test('a single event is done or not, and keeps its other fields', () {
      expect(eventDone(lunch, lunch.start), isFalse);
      final done = withEventDone(lunch, lunch.start, true);
      expect(eventDone(done, done.start), isTrue);
      expect(done.extra['colorNote'], 'kept');
      expect(done.title, 'Lunch');
      // It survives being stored and read back.
      final back = CalendarEvent.fromJson('lunch', done.toJson(), DateTime(2026, 11, 23))!;
      expect(eventDone(back, back.start), isTrue);
      final undone = withEventDone(done, done.start, false);
      expect(eventDone(undone, undone.start), isFalse);
      expect(undone.extra.containsKey('done'), isFalse);
    });

    test('a repeating event is done one day at a time', () {
      final tuesday = at10.add(const Duration(days: 1));
      final done = withEventDone(standup, tuesday, true);
      expect(eventDone(done, tuesday), isTrue);
      expect(eventDone(done, at10), isFalse);
      expect(eventDone(done, tuesday.add(const Duration(days: 1))), isFalse);
      final both = withEventDone(done, at10, true);
      expect(eventDone(both, at10), isTrue);
      expect(eventDone(both, tuesday), isTrue);
      final undone = withEventDone(withEventDone(both, at10, false), tuesday, false);
      expect(undone.extra.containsKey('doneOccurrences'), isFalse);
    });

    test('the calendar shows it crossed out, on that day only', () {
      final tuesday = at10.add(const Duration(days: 1));
      final entries = buildEntries(
        range: DateRange(DateTime(2026, 11, 23), DateTime(2026, 11, 26)),
        events: [
          withEventDone(lunch, lunch.start, true),
          withEventDone(standup, tuesday, true),
        ],
        calendars: const [ZtCalendarInfo.personal],
      );
      final lunchEntry = entries.singleWhere((e) => e.title == 'Lunch');
      expect(lunchEntry.done, isTrue);
      final standups = entries.where((e) => e.title == 'Stand-up').toList();
      expect(standups.map((e) => e.done), [false, true, false]);
      // A Planner block is crossed out by its own mark, not by this one.
      final blocks = buildEntries(
        range: DateRange(DateTime(2026, 11, 23), DateTime(2026, 11, 24)),
        events: [block('a:1', at10, done: true), block('a:2', at10.add(const Duration(hours: 2)))],
        calendars: const [ZtCalendarInfo.personal],
      );
      expect(blocks.map((e) => e.done), [true, false]);
    });
  });
}
