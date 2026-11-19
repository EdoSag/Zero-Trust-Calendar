import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_calendar/data/calendar_store.dart';
import 'package:zerotrust_calendar/data/linked_apps.dart';
import 'package:zerotrust_calendar/model/calendar_event.dart';
import 'package:zerotrust_calendar/planner/planner_ai.dart';
import 'package:zerotrust_calendar/planner/planner_controller.dart';
import 'package:zerotrust_calendar/planner/planner_model.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import 'planner_support.dart';

/// Answers with what a test set, and remembers what was sent.
class FakeAiBackend implements PlannerAiBackend {
  FakeAiBackend({this.available = true, this.answer = const {}, this.error});

  bool available;
  Map<String, Object?> answer;
  PlannerAiException? error;
  final sent = <Map<String, Object?>>[];
  int statusCalls = 0;

  @override
  Future<PlannerAiStatus> status() async {
    statusCalls++;
    return PlannerAiStatus(available: available, used: 12, limit: 300);
  }

  @override
  Future<Map<String, Object?>> ask(Map<String, Object?> body) async {
    sent.add(body);
    if (error != null) throw error!;
    return answer;
  }
}

/// Monday 23 November 2026, 8:00.
final monday = DateTime(2026, 11, 23, 8);

final allDayHours = {
  workHoursId: {
    for (var d = 1; d <= 7; d++) d: const [(0, 1440)],
  },
};

final on = PlannerSettings(enabled: true, hours: allDayHours, tasks: PlannerTasksChoice.all);

PlannerTask task(String id, {String? title, int? minutes = 60, DateTime? due}) =>
    PlannerTask(id: id, title: title ?? 'Task $id', minutes: minutes, due: due, createdAt: id);

CalendarEvent block(String id, String taskId, DateTime start, {int minutes = 60, String? title}) =>
    CalendarEvent(
      id: id,
      title: title ?? 'Task $taskId',
      start: start,
      end: start.add(Duration(minutes: minutes)),
      calendarId: plannerCalendarId,
      taskIds: [taskId],
      extra: {
        'plan': {'type': 'task', 'taskId': taskId, 'locked': false, 'done': false},
      },
    );

Map<String, Object?> change(String type, [Map<String, Object?> fields = const {}]) => {
  'type': type,
  'taskId': null,
  'blockId': null,
  'minutes': null,
  'priority': null,
  'date': null,
  'start': null,
  'end': null,
  'title': null,
  'weekday': null,
  'hours': null,
  'from': null,
  'to': null,
  'days': null,
  'question': null,
  'reason': null,
  ...fields,
};

Future<ProviderContainer> start(FakeAccount account, {FakeAiBackend? ai}) async {
  final container = ProviderContainer(
    overrides: [
      ...account.overrides,
      if (ai != null) plannerAiBackendProvider.overrideWithValue(ai),
    ],
  );
  addTearDown(container.dispose);
  container.listen(plannerControllerProvider, (_, _) {});
  await container.read(eventsProvider.future);
  await container.read(calendarsProvider.future);
  await container.read(plannerSettingsProvider.future);
  await container.read(plannerTasksProvider.future);
  await pumpEventQueue();
  return container;
}

void main() {
  group('settings and tasks', () {
    test('the AI switches are written only when on and never move blocks', () {
      const before = PlannerSettings(enabled: true);
      expect(before.toJson().keys, isNot(contains('aiGuess')));
      final after = before.copyWith(aiGuess: true, aiRequests: true, aiHideTitles: true);
      final json = after.toJson();
      expect(json['aiGuess'], isTrue);
      expect(json['aiRequests'], isTrue);
      expect(json['aiHideTitles'], isTrue);
      final back = PlannerSettings.fromJson(json, null);
      expect([back.aiGuess, back.aiRequests, back.aiHideTitles], [true, true, true]);
      expect(back.extra, isEmpty, reason: 'known keys, not kept as unknown');
      expect(after.planSignature, before.planSignature);
      // Settings saved by an older version read as off.
      final old = PlannerSettings.fromJson(before.toJson(), null);
      expect([old.aiGuess, old.aiRequests, old.aiHideTitles], [false, false, false]);
    });

    test('Calendar may write priority and the due date, and still nothing else', () {
      final json = {'title': 'Report', 'priority': 'medium', 'dueDate': '2026-11-27T00:00:00.000'};
      final out = PlannerTask.withPlanFields(json, {'priority': 'high', 'dueDate': null}, monday);
      expect(out['priority'], 'high');
      expect(out.containsKey('dueDate'), isFalse);
      expect(out['title'], 'Report');
      expect(() => PlannerTask.withPlanFields(json, {'title': 'x'}, monday), throwsArgumentError);
    });
  });

  group('what is sent', () {
    test('the table of days matches the test set: today, tomorrow, this, next', () {
      final en = aiDayTable(monday, 'en');
      expect(en, hasLength(14));
      expect(en.first, {'date': '2026-11-23', 'weekday': 1, 'label': 'today'});
      expect(en[1]['label'], 'tomorrow');
      expect(en[2]['label'], 'this Wednesday');
      expect(en[6]['label'], 'this Sunday');
      expect(en[7], {'date': '2026-11-30', 'weekday': 1, 'label': 'next Monday'});
      final he = aiDayTable(monday, 'he');
      expect(
        [he[0]['label'], he[1]['label'], he[2]['label'], he[7]['label']],
        ['היום', 'מחר', 'יום רביעי הזה', 'יום שני הבא'],
      );
    });

    test('hide titles sends labels only, and puts the titles back in the answer', () {
      final request = buildAiRequest(
        text: 'Move it after the event', // The sentence itself goes as written.
        now: monday,
        language: 'en',
        settings: on,
        tasks: [
          task('t1', title: 'Pay the dentist'),
          task('t2', title: 'Write report'),
        ],
        events: [
          block('b1', 't1', DateTime(2026, 11, 23, 10)),
          CalendarEvent(
            id: 'e1',
            title: 'Dr. Cohen',
            start: DateTime(2026, 11, 24, 9),
            end: DateTime(2026, 11, 24, 10),
          ),
        ],
        calendars: const [ZtCalendarInfo.personal],
        hideTitles: true,
      );
      final sent = jsonEncode(request.body);
      for (final secret in ['dentist', 'Write report', 'Cohen']) {
        expect(sent, isNot(contains(secret)));
      }
      final tasks = request.body['tasks'] as List;
      // Planned tasks first, by title: "Pay the dentist" before "Write report".
      expect([for (final t in tasks) (t as Map)['title']], ['Task A', 'Task B']);
      final blocks = request.body['blocks'] as List;
      expect((blocks.single as Map)['title'], 'Task A', reason: 'a block carries its task label');
      expect(((request.body['events'] as List).single as Map)['title'], 'Event A');
      expect(
        request.restore('Should Task A move before Event A?'),
        'Should Pay the dentist move before Dr. Cohen?',
      );
    });

    test('only coming blocks and events of busy calendars, in the two weeks', () {
      final request = buildAiRequest(
        text: 'x',
        now: monday,
        language: 'en',
        settings: on.copyWith(freeCalendarIds: {'free'}),
        tasks: [task('t1')],
        events: [
          block('past', 't1', DateTime(2026, 11, 20, 10)),
          block('soon', 't1', DateTime(2026, 11, 23, 10)),
          block('far', 't1', DateTime(2026, 12, 10, 10)),
          CalendarEvent(
            id: 'free-event',
            title: 'Free',
            start: DateTime(2026, 11, 24, 9),
            end: DateTime(2026, 11, 24, 10),
            calendarId: 'free',
          ),
        ],
        calendars: const [ZtCalendarInfo.personal],
        hideTitles: false,
      );
      expect([for (final b in request.body['blocks'] as List) (b as Map)['id']], ['soon']);
      expect(request.body['events'], isEmpty);
      expect(request.body['now'], '2026-11-23 08:00');
      expect((request.body['hours'] as List).first, {
        'hours': 'work',
        'weekday': 1,
        'from': '00:00',
        'to': '24:00',
      });
    });
  });

  group('what comes back', () {
    AiRequest request0() => buildAiRequest(
      text: 'x',
      now: monday,
      language: 'en',
      settings: on,
      tasks: [task('t1')],
      events: [block('b1', 't1', DateTime(2026, 11, 23, 10))],
      calendars: const [ZtCalendarInfo.personal],
      hideTitles: false,
    );

    test('changes about tasks, blocks or days that are not there are dropped', () async {
      final ai = FakeAiBackend(
        answer: {
          'changes': [
            change('set_length', {'taskId': 't1', 'minutes': 120}),
            change('set_length', {'taskId': 'gone', 'minutes': 120}),
            change('set_due', {'taskId': 't1', 'date': '2027-01-01'}),
            change('lock', {'blockId': 'b-gone'}),
            change('block_out', {'start': '2026-11-24 10:00', 'end': '2026-11-24 09:00'}),
            change('set_hours', {'weekday': 2, 'hours': 'work', 'from': '09:00', 'to': '16:00'}),
            change('explode'),
          ],
        },
      );
      final out = await askPlanner(ai, request0(), taskIds: {'t1'}, blockIds: {'b1'});
      expect([for (final c in out) c.type], [AiChangeType.setLength, AiChangeType.setHours]);
      expect(out.last.from, 9 * 60);
      expect(out.last.to, 16 * 60);
    });

    test('a question stands alone; "cannot" comes with the rest', () async {
      final ai = FakeAiBackend(
        answer: {
          'changes': [
            change('lock', {'blockId': 'b1'}),
            change('ask', {'question': 'This week or next?'}),
          ],
        },
      );
      final asked = await askPlanner(ai, request0(), taskIds: {'t1'}, blockIds: {'b1'});
      expect(asked.single.type, AiChangeType.ask);
      expect(asked.single.text, 'This week or next?');

      ai.answer = {
        'changes': [
          change('lock', {'blockId': 'b1'}),
          change('cannot', {'reason': "I can't invite people."}),
        ],
      };
      final partly = await askPlanner(ai, request0(), taskIds: {'t1'}, blockIds: {'b1'});
      expect(partly, hasLength(2));
      expect(partly.where((c) => c.applies), hasLength(1));
    });

    test('a guess is rounded to 5 minutes and kept in range', () async {
      final ai = FakeAiBackend(
        answer: {
          'guess': {'minutes': 47, 'confidence': 'medium'},
        },
      );
      final g = await guessTaskLength(
        ai,
        title: '  Call the bank ',
        language: 'he',
        usualMinutes: 30,
      );
      expect(g.minutes, 45);
      expect(ai.sent.single, {
        'job': 'guess',
        'lang': 'he',
        'title': 'Call the bank',
        'note': null,
        'usualMinutes': 30,
      });
      ai.answer = {'error': 'x'};
      expect(
        () => guessTaskLength(ai, title: 'x', language: 'en', usualMinutes: 30),
        throwsA(isA<PlannerAiException>()),
      );
    });
  });

  group('availability', () {
    test('hidden without the Planner, when the server says off, and on errors', () async {
      final ai = FakeAiBackend();
      final account = FakeAccount(settings: on);
      var container = await start(account, ai: ai);
      expect((await container.read(plannerAiStatusProvider.future))?.limit, 300);

      account.plannerAllowed = false;
      container = await start(account, ai: ai);
      final calls = ai.statusCalls;
      expect(await container.read(plannerAiStatusProvider.future), isNull);
      expect(ai.statusCalls, calls, reason: 'the server is not even asked');

      account.plannerAllowed = null;
      container = await start(account, ai: ai);
      expect(
        await container.read(plannerAiStatusProvider.future),
        isNull,
        reason: 'not known yet: not shown',
      );

      account.plannerAllowed = true;
      ai.available = false;
      container = await start(account, ai: ai);
      expect(await container.read(plannerAiStatusProvider.future), isNull);
    });
  });

  group('preview, apply and undo', () {
    DateTime soon(int hours) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, now.hour + hours);
    }

    AiChange parse(Map<String, Object?> raw) =>
        AiChange.fromJson(change(raw['type'] as String, raw))!;

    test('the preview counts what moves, and only what was ticked', () async {
      final account = FakeAccount(
        settings: on,
        tasks: [task('a', minutes: 60)],
        events: [block('a1', 'a', soon(2))],
      );
      final container = await start(account);
      final controller = container.read(plannerControllerProvider.notifier);
      final now = DateTime.now();
      final same = previewAiChanges(controller, on, const [], now: now)!;
      expect(same.same, isTrue);
      final longer = previewAiChanges(controller, on, [
        parse({'type': 'set_length', 'taskId': 'a', 'minutes': 180}),
      ], now: now)!;
      expect(longer.same, isFalse);
      expect(longer.added + longer.moved, greaterThan(0), reason: 'two more hours to place');
    });

    test('task changes are applied and undone exactly', () async {
      final due = DateTime(2026, 12, 4);
      final account = FakeAccount(
        settings: on,
        tasks: [
          PlannerTask(id: 'a', title: 'A', minutes: 60, createdAt: 'a'),
          PlannerTask(id: 'b', title: 'B', due: due, dueRaw: due.toIso8601String(), createdAt: 'b'),
          PlannerTask(id: 'c', title: 'C', createdAt: 'c'),
        ],
      );
      final container = await start(account);
      final undo = await container.read(plannerAiApplierProvider).apply([
        parse({'type': 'set_length', 'taskId': 'a', 'minutes': 120}),
        parse({'type': 'set_priority', 'taskId': 'a', 'priority': 'high'}),
        parse({'type': 'set_due', 'taskId': 'b', 'date': '2026-11-27'}),
        parse({'type': 'set_due', 'taskId': 'c', 'date': '2026-11-28'}),
        parse({'type': 'ask', 'question': 'never applied'}),
      ], busyTitle: 'Busy');
      PlannerTask byId(String id) => account.tasks.firstWhere((t) => t.id == id);
      expect(byId('a').minutes, 120);
      expect(byId('a').priority, PlanPriority.high);
      expect(byId('b').due, DateTime(2026, 11, 27));
      expect(byId('c').due, DateTime(2026, 11, 28));

      await undo();
      expect(byId('a').minutes, 60);
      expect(byId('a').priority, PlanPriority.medium);
      expect(byId('b').dueRaw, due.toIso8601String());
      expect(byId('c').due, isNull, reason: 'it had no due date');
    });

    test('a blocked-out time is an ordinary event, and undo removes it', () async {
      final account = FakeAccount(settings: on, tasks: [task('a')]);
      final container = await start(account);
      final undo = await container.read(plannerAiApplierProvider).apply([
        parse({'type': 'block_out', 'start': '2026-11-24 13:00', 'end': '2026-11-24 15:00'}),
      ], busyTitle: 'Busy');
      final added = account.events.where((e) => PlanMark.of(e) == null).single;
      expect(added.title, 'Busy');
      expect(added.calendarId, CalendarEvent.defaultCalendarId);
      expect(added.start, DateTime(2026, 11, 24, 13));
      await undo();
      expect(account.events.where((e) => e.id == added.id), isEmpty);
    });

    test('settings changes are saved once, and undo takes back only those', () async {
      final account = FakeAccount(settings: on, tasks: [task('a')]);
      final container = await start(account);
      account.log.clear();
      final undo = await container.read(plannerAiApplierProvider).apply([
        parse({'type': 'not_before', 'taskId': 'a', 'date': '2026-12-01'}),
        parse({'type': 'set_hours', 'weekday': 2, 'hours': 'work', 'from': '09:00', 'to': '00:00'}),
        parse({'type': 'set_hours', 'weekday': 3, 'hours': 'work', 'from': '00:00', 'to': '00:00'}),
        parse({
          'type': 'add_habit',
          'title': 'Walk',
          'minutes': 30,
          'days': [1, 3, 5],
          'from': '07:30',
        }),
      ], busyTitle: 'Busy');
      expect(account.log.where((l) => l == 'settings'), hasLength(1));
      final s = account.settings;
      expect(s.skips['a'], DateTime(2026, 12, 1));
      expect(s.rangesOn(workHoursId, 2), [(9 * 60, 24 * 60)]);
      expect(s.rangesOn(workHoursId, 3), isEmpty);
      final walk = s.habits.single;
      expect(
        [walk.title, walk.minutes, walk.days, walk.ideal],
        [
          'Walk',
          30,
          {1, 3, 5},
          7 * 60 + 30,
        ],
      );

      // Something else changed meanwhile: it stays.
      account.settings = account.settings.copyWith(defaultMinutes: 45);
      account.emit();
      await pumpEventQueue();
      await undo();
      final back = account.settings;
      expect(back.skips.containsKey('a'), isFalse);
      expect(back.hours, on.hours);
      expect(back.habits, isEmpty);
      expect(back.defaultMinutes, 45);
    });

    test('lock and done on blocks, and their undo', () async {
      final a1 = block('a1', 'a', soon(3));
      final account = FakeAccount(settings: on, tasks: [task('a'), task('b')], events: [a1]);
      final container = await start(account);
      final undo = await container.read(plannerAiApplierProvider).apply([
        parse({'type': 'lock', 'blockId': 'a1'}),
      ], busyTitle: 'Busy');
      expect(PlanMark.of(account.events.firstWhere((e) => e.id == 'a1'))!.locked, isTrue);
      await undo();
      expect(PlanMark.of(account.events.firstWhere((e) => e.id == 'a1'))!.locked, isFalse);

      final undoDone = await container.read(plannerAiApplierProvider).apply([
        parse({'type': 'mark_done', 'blockId': 'a1'}),
      ], busyTitle: 'Busy');
      expect(PlanMark.of(account.events.firstWhere((e) => e.id == 'a1'))!.done, isTrue);
      expect(
        account.tasks.firstWhere((t) => t.id == 'a').completed,
        isTrue,
        reason: 'its only hour was done',
      );
      await undoDone();
      final restored = account.events.firstWhere((e) => e.id == 'a1');
      expect(PlanMark.of(restored)!.done, isFalse);
      expect(restored.start, a1.start);
      expect(account.tasks.firstWhere((t) => t.id == 'a').completed, isFalse);
    });
  });
}
