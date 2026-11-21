import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:zt_scheduler/zt_scheduler.dart';

import '../data/linked_apps.dart';
import '../model/calendar_event.dart';
import 'planner_access.dart';
import 'planner_actions.dart';
import 'planner_controller.dart';
import 'planner_model.dart';

/// The Planner's AI helper (Plus, off by default): guesses a task's length
/// from its title, and turns one sentence into changes from a fixed menu.
///
/// The phone sends what is needed to a server function (`planner-ai` in
/// Zero-Trust-Core), which checks the plan and the monthly limit, asks the
/// model and checks the answer. Nothing is applied until the person has
/// seen every change and what it does to the plan; each applied change can
/// be undone. The server keeps counts only, never the text.
///
/// It stays hidden until the server says it is available
/// ([plannerAiStatusProvider]): the owner switches it on there.

/// What the server says about the helper for this account.
@immutable
class PlannerAiStatus {
  const PlannerAiStatus({required this.available, this.used = 0, this.limit = 0});

  factory PlannerAiStatus.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    int count(Object? v) => v is num ? v.toInt() : 0;
    return PlannerAiStatus(
      available: m['available'] == true,
      used: count(m['used']),
      limit: count(m['limit']),
    );
  }

  final bool available;

  /// Requests this month, and the monthly limit.
  final int used;
  final int limit;
}

/// Why a request to the helper failed: the server's error code (`off`,
/// `limit`, `budget`, `no_plan`, `refused`, `no_answer`, `busy`, ...) or
/// `network`.
class PlannerAiException implements Exception {
  const PlannerAiException(this.code);
  final String code;

  @override
  String toString() => 'PlannerAiException($code)';
}

/// The server side of the helper. Tests replace it.
abstract class PlannerAiBackend {
  Future<PlannerAiStatus> status();

  /// Sends [body] to the helper and returns its answer. Throws
  /// [PlannerAiException].
  Future<Map<String, Object?>> ask(Map<String, Object?> body);
}

class SupabasePlannerAiBackend implements PlannerAiBackend {
  SupabasePlannerAiBackend(this._client);
  final SupabaseClient _client;

  @override
  Future<PlannerAiStatus> status() async =>
      PlannerAiStatus.fromJson(await _client.rpc('zt_planner_ai_status'));

  @override
  Future<Map<String, Object?>> ask(Map<String, Object?> body) async {
    try {
      final res = await _client.functions.invoke('planner-ai', body: body);
      final data = res.data;
      if (data is Map && data['error'] is String) {
        throw PlannerAiException(data['error'] as String);
      }
      if (data is! Map) throw const PlannerAiException('no_answer');
      return data.cast<String, Object?>();
    } on FunctionException catch (e) {
      final details = e.details;
      throw PlannerAiException(
        details is Map && details['error'] is String ? details['error'] as String : 'server',
      );
    } on PlannerAiException {
      rethrow;
    } on Object {
      throw const PlannerAiException('network');
    }
  }
}

final plannerAiBackendProvider = Provider<PlannerAiBackend>(
  (ref) => SupabasePlannerAiBackend(Supabase.instance.client),
);

/// The helper's status when it can be offered: the account has the
/// Planner (Plus) and the server says the helper is on. Null otherwise,
/// and on any error, so the helper simply isn't shown.
final plannerAiStatusProvider = FutureProvider.autoDispose<PlannerAiStatus?>((ref) async {
  if (ref.watch(plannerAllowedProvider) != true) return null;
  try {
    final status = await ref.watch(plannerAiBackendProvider).status();
    return status.available ? status : null;
  } on Object {
    return null;
  }
});

// ---------------------------------------------------------------------------
// Length guesses

/// A guessed length, rounded to 5 minutes.
@immutable
class PlannerAiGuess {
  const PlannerAiGuess(this.minutes, this.confidence);
  final int minutes;

  /// `low`, `medium` or `high`.
  final String confidence;
}

/// Asks the helper how long [title] takes. Only the title (and the usual
/// length) is sent.
Future<PlannerAiGuess> guessTaskLength(
  PlannerAiBackend backend, {
  required String title,
  required String language,
  required int usualMinutes,
}) async {
  final trimmed = title.trim();
  if (trimmed.isEmpty) throw const PlannerAiException('bad_input');
  final answer = await backend.ask({
    'job': 'guess',
    'lang': language == 'he' ? 'he' : 'en',
    'title': trimmed.length > 300 ? trimmed.substring(0, 300) : trimmed,
    'note': null,
    'usualMinutes': usualMinutes.clamp(5, 600),
  });
  final g = answer['guess'];
  if (g is! Map || g['minutes'] is! num) throw const PlannerAiException('no_answer');
  final minutes = ((g['minutes'] as num).toDouble() / 5).round() * 5;
  return PlannerAiGuess(
    minutes.clamp(5, 2400),
    g['confidence'] is String ? g['confidence'] as String : 'low',
  );
}

// ---------------------------------------------------------------------------
// Requests

/// The kinds of change the helper may answer with. Anything else is
/// dropped.
enum AiChangeType {
  setLength('set_length'),
  setPriority('set_priority'),
  setDue('set_due'),
  notBefore('not_before'),
  lock('lock'),
  unlock('unlock'),
  markDone('mark_done'),
  blockOut('block_out'),
  setHours('set_hours'),
  addHabit('add_habit'),
  ask('ask'),
  cannot('cannot');

  const AiChangeType(this.wire);
  final String wire;

  static AiChangeType? of(Object? wire) => values.where((t) => t.wire == wire).firstOrNull;
}

/// One change the helper suggests, as it came back (already checked on the
/// server; checked again here against what is on the phone now).
@immutable
class AiChange {
  const AiChange({
    required this.type,
    this.taskId,
    this.blockId,
    this.minutes,
    this.priority,
    this.date,
    this.start,
    this.end,
    this.title,
    this.weekday,
    this.hours,
    this.from,
    this.to,
    this.days,
    this.text,
  });

  final AiChangeType type;
  final String? taskId;
  final String? blockId;
  final int? minutes;
  final PlanPriority? priority;

  /// A day ([setDue], [notBefore]), local midnight.
  final DateTime? date;
  final DateTime? start;
  final DateTime? end;
  final String? title;
  final int? weekday;

  /// `work` or `personal`.
  final String? hours;

  /// Minutes of the day.
  final int? from;
  final int? to;
  final Set<int>? days;

  /// The question ([AiChangeType.ask]) or the reason
  /// ([AiChangeType.cannot]), in the person's language.
  final String? text;

  /// Ask and cannot are said, not applied.
  bool get applies => type != AiChangeType.ask && type != AiChangeType.cannot;

  /// The change as sent by the server, or null when it makes no sense.
  static AiChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = AiChangeType.of(raw['type']);
    if (type == null) return null;
    String? str(String k) {
      final v = raw[k];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    int? num_(String k) => raw[k] is num ? (raw[k] as num).toInt() : null;
    return AiChange(
      type: type,
      taskId: str('taskId'),
      blockId: str('blockId'),
      minutes: num_('minutes'),
      priority: switch (raw['priority']) {
        'high' => PlanPriority.high,
        'medium' => PlanPriority.medium,
        'low' => PlanPriority.low,
        _ => null,
      },
      date: _day(str('date')),
      start: _dateTime(str('start')),
      end: _dateTime(str('end')),
      title: str('title'),
      weekday: num_('weekday'),
      hours: raw['hours'] == 'work' || raw['hours'] == 'personal' ? raw['hours'] as String : null,
      from: _minuteOfDay(str('from')),
      to: _minuteOfDay(str('to')),
      days: raw['days'] is List
          ? {
              for (final d in raw['days'] as List)
                if (d is num && d >= 1 && d <= 7) d.toInt(),
            }
          : null,
      text: str(type == AiChangeType.ask ? 'question' : 'reason'),
    );
  }

  AiChange withText(String? text) => AiChange(
    type: type,
    taskId: taskId,
    blockId: blockId,
    minutes: minutes,
    priority: priority,
    date: date,
    start: start,
    end: end,
    title: title,
    weekday: weekday,
    hours: hours,
    from: from,
    to: to,
    days: days,
    text: text,
  );
}

DateTime? _day(String? s) {
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

DateTime? _dateTime(String? s) {
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(s)) return null;
  final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
  return d == null ? null : DateTime(d.year, d.month, d.day, d.hour, d.minute);
}

int? _minuteOfDay(String? s) {
  if (s == null || !RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) return null;
  final h = int.parse(s.substring(0, 2)), m = int.parse(s.substring(3));
  if (h > 23 || m > 59) return null;
  return h * 60 + m;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _time(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
String _stamp(DateTime d) => '${_date(d)} ${_time(d.hour * 60 + d.minute)}';

/// How far ahead the helper sees, in days.
const aiRequestDays = 14;

/// What is sent for a request, and how to put titles back in what comes
/// back when "Hide titles" is on.
@immutable
class AiRequest {
  const AiRequest(this.body, this.labels);

  /// The JSON body for the server.
  final Map<String, Object?> body;

  /// Label (Task A, Event B, ...) to the title it stands for. Empty when
  /// titles are sent as they are.
  final Map<String, String> labels;

  /// [text] (a question or a reason from the helper) with the labels
  /// replaced by the titles they stand for. Longer labels first, so
  /// "Task AB" isn't read as "Task A" and "B".
  String restore(String text) {
    var out = text;
    final keys = labels.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      out = out.replaceAll(k, labels[k]!);
    }
    return out;
  }
}

const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _weekdaysHe = [
  'יום שני',
  'יום שלישי',
  'יום רביעי',
  'יום חמישי',
  'יום שישי',
  'שבת',
  'יום ראשון',
];

/// The table of days the helper takes dates from (it never works dates
/// out itself): today, tomorrow, then "this Monday" and so on for the rest
/// of the first week, and "next Monday" and so on after it.
List<Map<String, Object?>> aiDayTable(DateTime now, String language) {
  final he = language == 'he';
  return [
    for (var i = 0; i < aiRequestDays; i++)
      () {
        final d = DateTime(now.year, now.month, now.day + i);
        final name = (he ? _weekdaysHe : _weekdaysEn)[d.weekday - 1];
        final label = switch (i) {
          0 => he ? 'היום' : 'today',
          1 => he ? 'מחר' : 'tomorrow',
          < 7 => he ? '$name הזה' : 'this $name',
          _ => he ? '$name הבא' : 'next $name',
        };
        return {'date': _date(d), 'weekday': d.weekday, 'label': label};
      }(),
  ];
}

/// "A", "B", ... "Z", "AA", "AB", ...
String _letters(int i) {
  var n = i + 1;
  var out = '';
  while (n > 0) {
    n--;
    out = String.fromCharCode(65 + n % 26) + out;
    n ~/= 26;
  }
  return out;
}

/// Builds the request for [text]: the days table, the hours, the open
/// tasks (planned ones first), the coming blocks and the busy events. With
/// [hideTitles], every title is replaced by a label on the phone, and
/// [AiRequest.restore] puts them back in the answer.
AiRequest buildAiRequest({
  required String text,
  required DateTime now,
  required String language,
  required PlannerSettings settings,
  required List<PlannerTask> tasks,
  required List<CalendarEvent> events,
  required List<ZtCalendarInfo> calendars,
  required bool hideTitles,
}) {
  final he = language == 'he';
  final today = DateTime(now.year, now.month, now.day);
  final until = DateTime(today.year, today.month, today.day + aiRequestDays);
  final labels = <String, String>{};
  final taskLabels = <String, String>{};
  final habitLabels = <String, String>{};
  var events_ = 0;

  String taskTitle(PlannerTask t) {
    if (!hideTitles) return t.title;
    return taskLabels.putIfAbsent(t.id, () {
      final label = '${he ? 'משימה' : 'Task'} ${_letters(taskLabels.length)}';
      labels[label] = t.title;
      return label;
    });
  }

  String habitTitle(String id, String title) {
    if (!hideTitles) return title;
    return habitLabels.putIfAbsent(id, () {
      final label = '${he ? 'הרגל' : 'Habit'} ${_letters(habitLabels.length)}';
      labels[label] = title;
      return label;
    });
  }

  String eventTitle(String title) {
    if (!hideTitles) return title;
    final label = '${he ? 'אירוע' : 'Event'} ${_letters(events_++)}';
    labels[label] = title;
    return label;
  }

  String cut(String s) => s.length > 300 ? s.substring(0, 300) : s;

  final open =
      [
        for (final t in tasks)
          if (!t.completed) t,
      ]..sort((a, b) {
        final pa = a.plannedUnder(settings.tasks), pb = b.plannedUnder(settings.tasks);
        if (pa != pb) return pa ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
  final sentTasks = open.take(60).toList();
  final byId = {for (final t in sentTasks) t.id: t};

  final blocks = <Map<String, Object?>>[];
  final busy = <Map<String, Object?>>[];
  final skip = {
    ...settings.freeCalendarIds,
    for (final c in calendars)
      if (c.hidden) c.id,
  };
  final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
  for (final e in sorted) {
    final mark = PlanMark.of(e);
    if (mark != null) {
      if (!e.end.isAfter(today) || !e.start.isBefore(until) || blocks.length >= 120) continue;
      final task = mark.isHabit ? null : byId[mark.itemId];
      blocks.add({
        'id': e.id,
        'title': cut(
          mark.isHabit
              ? habitTitle(mark.itemId, e.title)
              : task != null
              ? taskTitle(task)
              : (hideTitles ? eventTitle(e.title) : e.title),
        ),
        'taskId': mark.isHabit || task == null ? null : task.id,
        'start': _stamp(e.start),
        'end': _stamp(e.end),
        'locked': mark.locked,
        'done': mark.done,
      });
      continue;
    }
    if (skip.contains(e.calendarId)) continue;
    for (final (s, end) in e.occurrencesBetween(today, until)) {
      if (busy.length >= 120) break;
      busy.add({'title': cut(eventTitle(e.title)), 'start': _stamp(s), 'end': _stamp(end)});
    }
  }
  busy.sort((a, b) => (a['start'] as String).compareTo(b['start'] as String));

  return AiRequest({
    'job': 'request',
    'lang': he ? 'he' : 'en',
    'text': text.length > 500 ? text.substring(0, 500) : text,
    'now': _stamp(now),
    'days': aiDayTable(now, language),
    'hours': [
      for (final id in const [workHoursId, personalHoursId])
        for (final wd in [1, 2, 3, 4, 5, 6, 7])
          for (final (s, e) in settings.rangesOn(id, wd))
            {'hours': id, 'weekday': wd, 'from': _time(s), 'to': _time(e)},
    ].take(56).toList(),
    'tasks': [
      for (final t in sentTasks)
        {
          'id': t.id,
          'title': cut(taskTitle(t)),
          'minutes': t.minutes,
          'due': t.due == null ? null : _date(t.due!),
          'priority': switch (t.priority) {
            PlanPriority.critical || PlanPriority.high => 'high',
            PlanPriority.medium => 'medium',
            PlanPriority.low => 'low',
          },
        },
    ],
    'blocks': blocks,
    'events': busy,
  }, labels);
}

/// Sends [request] and returns the changes that still make sense on this
/// phone: known tasks and blocks, days in the table, values in range. A
/// question stands alone. Titles hidden for the request are put back in
/// the helper's words.
Future<List<AiChange>> askPlanner(
  PlannerAiBackend backend,
  AiRequest request, {
  required Set<String> taskIds,
  required Set<String> blockIds,
}) async {
  final answer = await backend.ask(request.body);
  final raw = answer['changes'];
  if (raw is! List) throw const PlannerAiException('no_answer');
  final days = {for (final d in request.body['days'] as List) (d as Map)['date'] as String};
  bool inTable(DateTime? d) => d != null && days.contains(_date(d));
  final out = <AiChange>[];
  for (final r in raw.take(20)) {
    final c = AiChange.fromJson(r);
    if (c == null) continue;
    final ok = switch (c.type) {
      AiChangeType.setLength =>
        taskIds.contains(c.taskId) && c.minutes != null && c.minutes! >= 5 && c.minutes! <= 2400,
      AiChangeType.setPriority => taskIds.contains(c.taskId) && c.priority != null,
      AiChangeType.setDue ||
      AiChangeType.notBefore => taskIds.contains(c.taskId) && inTable(c.date),
      AiChangeType.lock ||
      AiChangeType.unlock ||
      AiChangeType.markDone => blockIds.contains(c.blockId),
      AiChangeType.blockOut =>
        c.start != null &&
            c.end != null &&
            c.start!.isBefore(c.end!) &&
            inTable(c.start) &&
            inTable(c.end),
      AiChangeType.setHours =>
        c.weekday != null &&
            c.weekday! >= 1 &&
            c.weekday! <= 7 &&
            c.hours != null &&
            c.from != null &&
            c.to != null &&
            (c.to == 0 || c.from! < c.to!),
      AiChangeType.addHabit =>
        c.title != null &&
            c.minutes != null &&
            c.minutes! >= 5 &&
            c.minutes! <= 480 &&
            (c.days?.isNotEmpty ?? false) &&
            c.from != null,
      AiChangeType.ask || AiChangeType.cannot => c.text != null,
    };
    if (!ok) continue;
    out.add(c.text == null ? c : c.withText(request.restore(c.text!)));
  }
  final question = out.where((c) => c.type == AiChangeType.ask).firstOrNull;
  return question != null ? [question] : out;
}

// ---------------------------------------------------------------------------
// Preview and applying

/// The hours of [settings] with [c] (a set_hours change) applied: that
/// weekday's ranges replaced by one, or none for "00:00 to 00:00".
Map<String, Map<int, List<MinuteRange>>> _hoursWith(PlannerSettings settings, AiChange c) {
  final id = c.hours!;
  final to = c.to == 0 ? 24 * 60 : c.to!;
  final week = {...?settings.hours[id]};
  week[c.weekday!] = c.from == 0 && c.to == 0 ? const [] : [(c.from!, to)];
  return {...settings.hours, id: week};
}

PlannerHabit _habitOf(AiChange c, String id) {
  final from = c.from!;
  final minutes = c.minutes!;
  return PlannerHabit(
    id: id,
    title: c.title!,
    minutes: minutes,
    days: c.days!,
    ideal: from,
    earliest: (from - 60).clamp(0, 24 * 60),
    latest: (from + minutes + 60).clamp(0, 24 * 60),
  );
}

CalendarEvent _blockOutEvent(AiChange c, String id, String fallbackTitle) =>
    CalendarEvent(id: id, title: c.title ?? fallbackTitle, start: c.start!, end: c.end!);

/// What the chosen changes do to the plan.
@immutable
class AiPreview {
  const AiPreview({this.moved = 0, this.added = 0, this.removed = 0});
  final int moved;
  final int added;
  final int removed;

  bool get same => moved == 0 && added == 0 && removed == 0;
}

/// The blocks a plan would have, by id.
Map<String, CalendarEvent> _byId(List<CalendarEvent> blocks) => {for (final b in blocks) b.id: b};

/// Runs the Planner on [changes] without saving anything and counts the
/// blocks that would move, be added or go. Null while the Planner's data is
/// still loading.
AiPreview? previewAiChanges(
  PlannerController controller,
  PlannerSettings settings,
  List<AiChange> changes, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final before = controller.previewWith(settings, now: at);
  if (before == null) return null;
  final applied = changes.where((c) => c.applies).toList();
  final next = _settingsWith(
    settings,
    applied,
    at,
    habitIds: (c) => 'preview-${applied.indexOf(c)}',
  );
  final after = controller.previewWith(
    next,
    now: at,
    // New hours or a new habit plan the week afresh, as the next run will.
    rebuild: next.planSignature != settings.planSignature,
    tasks: (tasks) => [for (final t in tasks) _taskWith(t, applied)],
    events: (events) => [
      for (final e in events) _eventWith(e, applied, at),
      for (final (i, c) in applied.indexed)
        if (c.type == AiChangeType.blockOut) _blockOutEvent(c, 'preview-busy-$i', ''),
    ],
  );
  if (after == null) return null;
  final b = _byId(before), a = _byId(after);
  var moved = 0, added = 0, removed = 0;
  for (final e in a.values) {
    final old = b[e.id];
    if (old == null) {
      added++;
    } else if (old.start != e.start || old.end != e.end) {
      moved++;
    }
  }
  for (final id in b.keys) {
    if (!a.containsKey(id)) removed++;
  }
  return AiPreview(moved: moved, added: added, removed: removed);
}

PlannerSettings _settingsWith(
  PlannerSettings settings,
  List<AiChange> changes,
  DateTime now, {
  required String Function(AiChange) habitIds,
}) {
  var s = settings;
  for (final c in changes) {
    switch (c.type) {
      case AiChangeType.notBefore:
        s = s.copyWith(skips: {...s.skipsAfter(now), c.taskId!: c.date!});
      case AiChangeType.setHours:
        s = s.copyWith(hours: _hoursWith(s, c));
      case AiChangeType.addHabit:
        s = s.copyWith(habits: [...s.habits, _habitOf(c, habitIds(c))]);
      default:
    }
  }
  return s;
}

PlannerTask _taskWith(PlannerTask t, List<AiChange> changes) {
  var out = t;
  for (final c in changes) {
    if (c.taskId != t.id) continue;
    switch (c.type) {
      case AiChangeType.setLength:
        out = out.copyWith(minutes: c.minutes);
      case AiChangeType.setPriority:
        out = out.copyWith(priority: c.priority);
      case AiChangeType.setDue:
        final old = out.due;
        out = out.copyWith(
          due: DateTime(c.date!.year, c.date!.month, c.date!.day, old?.hour ?? 0, old?.minute ?? 0),
          dueHasTime: out.dueHasTime,
        );
      default:
    }
  }
  return out;
}

CalendarEvent _eventWith(CalendarEvent e, List<AiChange> changes, DateTime at) {
  var mark = PlanMark.of(e);
  if (mark == null) return e;
  for (final c in changes) {
    if (c.blockId != e.id) continue;
    if (c.type == AiChangeType.markDone && !mark!.done) {
      final end = DateTime(at.year, at.month, at.day, at.hour, at.minute);
      final from = mark.started;
      if (from != null && mark.runningAt(at)) {
        // Being timed: as PlannerActions.setDone does, the timer stops and
        // the block is the time that was really worked.
        e = e.copyWith(
          start: from,
          end: end.isAfter(from) ? end : from.add(const Duration(minutes: 1)),
        );
        mark = mark.copyWith(started: null);
      } else if (e.start.isAfter(at)) {
        // Done ahead of time: as PlannerActions.setDone does, the block
        // moves to end now, and its old time is free for other work.
        e = e.copyWith(start: end.subtract(e.duration), end: end);
      }
    }
    mark = switch (c.type) {
      AiChangeType.lock => mark!.copyWith(locked: true, reason: PlanReason.locked),
      AiChangeType.unlock => mark!.copyWith(locked: false, reason: PlanReason.kept),
      AiChangeType.markDone => mark!.copyWith(done: true, reason: PlanReason.done),
      _ => mark,
    };
  }
  return e.copyWith(extra: {...e.extra, 'plan': mark!.toJson()});
}

/// Applies the helper's changes, after the person confirmed them, and
/// returns how to undo them (newest first). Settings changes are saved
/// together, so the week is planned once.
class PlannerAiApplier {
  PlannerAiApplier(this._ref);
  final Ref _ref;

  PlannerSettings get _settings =>
      _ref.read(plannerSettingsProvider).value ?? const PlannerSettings();

  PlannerTask? _task(String? id) =>
      (_ref.read(plannerTasksProvider).value?.tasks ?? const <PlannerTask>[])
          .where((t) => t.id == id)
          .firstOrNull;

  CalendarEvent? _block(String? id) =>
      _ref.read(plannerBlocksProvider).where((b) => b.id == id).firstOrNull;

  /// Applies [changes]. [busyTitle] names a blocked-out time the helper
  /// gave no title. Returns the undo; a change whose task or block is gone
  /// is skipped. When a write fails, what was already written is undone
  /// before the error is thrown, so nothing is left half applied.
  Future<Future<void> Function()> apply(
    List<AiChange> changes, {
    required String busyTitle,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final undo = <Future<void> Function()>[];
    try {
      await _applyAll(changes, busyTitle, at, undo);
    } catch (_) {
      for (final u in undo.reversed) {
        try {
          await u();
        } on Object {
          // Keep undoing the rest.
        }
      }
      rethrow;
    }
    return () async {
      for (final u in undo.reversed) {
        await u();
      }
    };
  }

  Future<void> _applyAll(
    List<AiChange> changes,
    String busyTitle,
    DateTime at,
    List<Future<void> Function()> undo,
  ) async {
    final actions = _ref.read(plannerActionsProvider);
    final writeTask = _ref.read(plannerTaskWriterProvider);
    final writer = _ref.read(plannerWriterProvider);

    for (final c in changes.where((c) => c.applies)) {
      switch (c.type) {
        case AiChangeType.setLength:
          final t = _task(c.taskId);
          if (t == null) continue;
          await writeTask(t.id, {'planMinutes': c.minutes});
          undo.add(() => writeTask(t.id, {'planMinutes': t.minutes}));
        case AiChangeType.setPriority:
          final t = _task(c.taskId);
          if (t == null) continue;
          await writeTask(t.id, {'priority': c.priority!.name});
          undo.add(() => writeTask(t.id, {'priority': t.priority.name}));
        case AiChangeType.setDue:
          final t = _task(c.taskId);
          if (t == null) continue;
          await _ref.read(plannerTaskDueWriterProvider)(t.id, c.date!);
          // Exactly as it was, or no due date again.
          undo.add(() => writeTask(t.id, {'dueDate': t.dueRaw}));
        case AiChangeType.lock || AiChangeType.unlock:
          final b = _block(c.blockId);
          if (b == null) continue;
          final locked = c.type == AiChangeType.lock;
          await actions.setLocked(b, locked);
          undo.add(() => actions.restore(b));
        case AiChangeType.markDone:
          final b = _block(c.blockId);
          if (b == null || (PlanMark.of(b)?.done ?? true)) continue;
          final finished = await actions.setDone(b, true, now: at);
          undo.add(() async {
            await actions.restore(b);
            if (finished != null) await actions.reopenTask(finished);
          });
        case AiChangeType.blockOut:
          final id = const Uuid().v4();
          await writer.saveBlock(_blockOutEvent(c, id, busyTitle));
          undo.add(() => writer.deleteBlock(id));
        default:
      }
    }

    // not_before, set_hours and add_habit change the settings: one save.
    final settingsChanges = changes
        .where(
          (c) => const {
            AiChangeType.notBefore,
            AiChangeType.setHours,
            AiChangeType.addHabit,
          }.contains(c.type),
        )
        .where((c) => c.type != AiChangeType.notBefore || _task(c.taskId) != null)
        .toList();
    if (settingsChanges.isNotEmpty) {
      final before = _settings;
      final habitIds = {for (final c in settingsChanges) c: const Uuid().v4()};
      // Saved as they are: the next run plans afresh only when the hours
      // or habits changed, which is what the preview showed.
      await writer.saveSettings(
        _settingsWith(before, settingsChanges, at, habitIds: (c) => habitIds[c]!),
      );
      final skipped = {
        for (final c in settingsChanges)
          if (c.type == AiChangeType.notBefore) c.taskId!,
      };
      final hoursTouched = {
        for (final c in settingsChanges)
          if (c.type == AiChangeType.setHours) c.hours!,
      };
      undo.add(() {
        // Only what these changes touched goes back; anything else changed
        // since stays.
        final now_ = _settings;
        final skips = {...now_.skips};
        for (final id in skipped) {
          if (before.skips[id] case final old?) {
            skips[id] = old;
          } else {
            skips.remove(id);
          }
        }
        return writer.saveSettings(
          now_.copyWith(
            skips: skips,
            hours: {...now_.hours, for (final id in hoursTouched) id: before.hours[id] ?? const {}},
            habits: [
              for (final h in now_.habits)
                if (!habitIds.values.contains(h.id)) h,
            ],
          ),
        );
      });
    }
  }
}

final plannerAiApplierProvider = Provider<PlannerAiApplier>(PlannerAiApplier.new);
