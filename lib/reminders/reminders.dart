import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/calendar_event.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// One reminder the OS should show at [at], for one occurrence of an event.
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.eventId,
    required this.occurrence,
    required this.at,
    required this.title,
    required this.body,
    this.hasPlace = false,
    this.hasNote = false,
    this.hasGuests = false,
  });

  final String eventId;
  final DateTime occurrence;
  final DateTime at;

  /// The event's title, or "Event" when titles are off in settings. The
  /// only event text that leaves the vault: the OS has to hold it to show
  /// the reminder while Calendar is locked.
  final String title;

  /// "14:00 to 15:00", "Tomorrow, all day".
  final String body;

  /// Which buttons the reminder gets besides Snooze: "Map", "Note",
  /// "Running late". Only whether the event has a place, a linked note or
  /// guests reaches the OS, never what they are.
  final bool hasPlace;
  final bool hasNote;
  final bool hasGuests;

  List<String> get actions => [
    ReminderAction.snooze,
    if (hasPlace) ReminderAction.map,
    if (hasNote) ReminderAction.note,
    if (hasGuests) ReminderAction.late,
  ];

  int get notificationId =>
      idFor('$eventId|${occurrence.toUtc().toIso8601String()}|'
          '${at.toUtc().toIso8601String()}');

  /// FNV-1a, so the id is the same on every run (String.hashCode isn't).
  static int idFor(String key) {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  /// Carried on the notification so a tap can open the event, and Snooze
  /// can show it again. The title and body are already in the
  /// notification itself.
  String get payload => jsonEncode({
    'e': eventId,
    'o': occurrence.toUtc().toIso8601String(),
    't': title,
    'b': body,
    'a': actions.join(','),
  });

  static (String, DateTime?)? parsePayload(String? payload) {
    final p = ReminderPayload.parse(payload);
    return p == null ? null : (p.eventId, p.occurrence);
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.notificationId == notificationId &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(notificationId, title, body, payload);
}

/// Buttons on a reminder.
abstract final class ReminderAction {
  static const snooze = 'snooze';
  static const map = 'map';
  static const note = 'note';
  static const late = 'late';

  static Map<String, String> get labels => {
    snooze: currentL10n.snooze10Min,
    map: currentL10n.map,
    note: currentL10n.note,
    late: currentL10n.runningLate,
  };

  static const snoozeFor = Duration(minutes: 10);
}

/// A reminder's payload, read back from a tap or a button.
@immutable
class ReminderPayload {
  const ReminderPayload({
    required this.eventId,
    this.occurrence,
    this.title = 'Event',
    this.body = '',
    this.actions = const [],
    this.snoozed = false,
  });

  final String eventId;
  final DateTime? occurrence;
  final String title;
  final String body;
  final List<String> actions;

  /// A reminder snoozed from its notification; kept by [ReminderScheduler.sync].
  final bool snoozed;

  String encode() => jsonEncode({
    'e': eventId,
    if (occurrence != null) 'o': occurrence!.toUtc().toIso8601String(),
    't': title,
    'b': body,
    'a': actions.join(','),
    if (snoozed) 's': 1,
  });

  /// Also reads the older `eventId|occurrence` payloads.
  static ReminderPayload? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('{')) {
      try {
        final m = jsonDecode(payload) as Map<String, Object?>;
        final id = m['e'];
        if (id is! String) return null;
        return ReminderPayload(
          eventId: id,
          occurrence: DateTime.tryParse((m['o'] as String?) ?? '')?.toLocal(),
          title: (m['t'] as String?) ?? currentL10n.event,
          body: (m['b'] as String?) ?? '',
          actions: [
            for (final a in ((m['a'] as String?) ?? '').split(','))
              if (a.isNotEmpty) a,
          ],
          snoozed: m['s'] == 1,
        );
      } on Object {
        return null;
      }
    }
    final parts = payload.split('|');
    return ReminderPayload(
      eventId: parts.first,
      occurrence: parts.length > 1 ? DateTime.tryParse(parts[1])?.toLocal() : null,
    );
  }
}

/// A tap on a reminder ([action] null) or on one of its buttons.
typedef ReminderTap = ({String eventId, DateTime? occurrence, String? action});

/// All-day events remind relative to this time on their first day.
const allDayReminderHour = 9;

/// The reminders [events] want between [now] and [now] + [horizon], soonest
/// first and at most [max] (Android keeps at most 500 alarms per app).
List<ScheduledReminder> remindersFor(
  Iterable<CalendarEvent> events, {
  required DateTime now,
  required String Function(CalendarEvent event, DateTime start) bodyFor,
  bool showTitles = true,
  Set<String> hiddenCalendars = const {},
  Duration horizon = const Duration(days: 30),
  int max = 150,
}) {
  final out = <ScheduledReminder>[];
  final until = now.add(horizon);
  for (final e in events) {
    if (e.reminders.isEmpty || hiddenCalendars.contains(e.calendarId)) {
      continue;
    }
    final longest = e.reminders.reduce((a, b) => a > b ? a : b);
    // Occurrences whose earliest reminder could fall in [now, until).
    // (All-day reminders fire up to 9 hours after their start.)
    final from = now.subtract(const Duration(days: 1));
    final to = until.add(Duration(minutes: longest + 24 * 60));
    final starts = e.occurrenceStarts(from, to);
    for (final s in starts) {
      final base = e.allDay
          ? DateTime(s.year, s.month, s.day, allDayReminderHour)
          : s;
      for (final minutes in e.reminders.toSet()) {
        final at = base.subtract(Duration(minutes: minutes));
        if (at.isAfter(now) && at.isBefore(until)) {
          final title = e.title.trim();
          out.add(
            ScheduledReminder(
              eventId: e.id,
              occurrence: s,
              at: at,
              title: showTitles && title.isNotEmpty ? title : currentL10n.event,
              body: bodyFor(e, s),
              hasPlace: e.location.trim().isNotEmpty,
              hasNote: e.noteIds.isNotEmpty,
              hasGuests: e.contactIds.isNotEmpty || e.guestEmails.isNotEmpty,
            ),
          );
        }
      }
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > max ? out.sublist(0, max) : out;
}

/// Hands event reminders to the OS so they fire while Calendar is closed or
/// locked.
abstract interface class ReminderScheduler {
  /// Makes the OS's pending reminders exactly [reminders].
  Future<void> sync(List<ScheduledReminder> reminders);

  /// Drops every reminder (sign-out).
  Future<void> cancelAll();

  /// Asks for notification (and exact alarm) permission. False when off.
  Future<bool> requestPermission();

  /// Reminder taps and button presses, including the one that launched
  /// the app.
  Stream<ReminderTap> get taps;
}

/// For tests and platforms without notifications.
class NoopReminderScheduler implements ReminderScheduler {
  List<ScheduledReminder> scheduled = const [];

  @override
  Future<void> sync(List<ScheduledReminder> reminders) async =>
      scheduled = reminders;

  @override
  Future<void> cancelAll() async => scheduled = const [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Stream<ReminderTap> get taps => const Stream.empty();
}

class LocalNotificationsReminderScheduler implements ReminderScheduler {
  LocalNotificationsReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<ReminderTap>.broadcast();
  ReminderTap? _launch;
  Future<void>? _ready;

  static AndroidNotificationDetails get _channel => AndroidNotificationDetails(
    'event_reminders',
    currentL10n.eventReminders,
    channelDescription: currentL10n.remindersBeforeYourEvents,
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.event,
    // The lock screen shows "ZT Calendar", not the event's title.
    visibility: NotificationVisibility.private,
  );

  static NotificationDetails detailsFor(List<String> actions) => NotificationDetails(
    android: AndroidNotificationDetails(
      _channel.channelId,
      _channel.channelName,
      channelDescription: _channel.channelDescription,
      importance: _channel.importance,
      priority: _channel.priority,
      category: _channel.category,
      visibility: _channel.visibility,
      actions: [
        for (final a in actions)
          AndroidNotificationAction(
            a,
            ReminderAction.labels[a] ?? a,
            // Snooze happens without opening the app; the others need the
            // unlocked app (the place, note and guests stay in the vault).
            showsUserInterface: a != ReminderAction.snooze,
            cancelNotification: true,
          ),
      ],
    ),
    iOS: const DarwinNotificationDetails(),
  );

  static ReminderTap? _tapFrom(NotificationResponse response) {
    final p = ReminderPayload.parse(response.payload);
    if (p == null) return null;
    final action = response.actionId;
    return (
      eventId: p.eventId,
      occurrence: p.occurrence,
      action: action == null || action.isEmpty ? null : action,
    );
  }

  Future<void> _init() => _ready ??= () async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Permission is asked when the first reminder is set, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == ReminderAction.snooze) {
          snoozeReminder(_plugin, response).ignore();
          return;
        }
        final tap = _tapFrom(response);
        if (tap != null) _taps.add(tap);
      },
      onDidReceiveBackgroundNotificationResponse: onReminderButtonInBackground,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _launch = _tapFrom(response);
    }
  }();

  Future<void> initialize() => _init();

  @override
  Stream<ReminderTap> get taps async* {
    try {
      await _init();
    } on Object {
      return;
    }
    final launched = _launch;
    _launch = null;
    if (launched != null) yield launched;
    yield* _taps.stream;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _android;
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? true;
      if (granted && !(await android.canScheduleExactNotifications() ?? true)) {
        await android.requestExactAlarmsPermission();
      }
      return granted;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return true;
  }

  @override
  Future<void> sync(List<ScheduledReminder> reminders) async {
    await _init();
    final wanted = {for (final r in reminders) r.notificationId: r};
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      // Snoozed from the notification: left to fire.
      if (ReminderPayload.parse(request.payload)?.snoozed ?? false) continue;
      final want = wanted[request.id];
      if (want == null) {
        await _plugin.cancel(id: request.id);
      } else if (request.title == want.title &&
          request.body == want.body &&
          request.payload == want.payload) {
        wanted.remove(request.id); // Already scheduled as it should be.
      }
    }
    if (wanted.isEmpty) return;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    for (final r in wanted.values) {
      await _plugin.zonedSchedule(
        id: r.notificationId,
        title: r.title,
        body: r.body,
        payload: r.payload,
        // An absolute instant, so the device's time zone doesn't matter.
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: detailsFor(r.actions),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

/// Shows the reminder again in [ReminderAction.snoozeFor], as the same
/// text, without opening the app (it may be locked).
Future<void> snoozeReminder(
  FlutterLocalNotificationsPlugin plugin,
  NotificationResponse response,
) async {
  final p = ReminderPayload.parse(response.payload);
  if (p == null) return;
  final again = DateTime.now().toUtc().add(ReminderAction.snoozeFor);
  final payload = ReminderPayload(
    eventId: p.eventId,
    occurrence: p.occurrence,
    title: p.title,
    body: p.body,
    actions: p.actions,
    snoozed: true,
  );
  await plugin.zonedSchedule(
    id: ScheduledReminder.idFor('snooze|${p.eventId}|${p.occurrence?.toUtc().toIso8601String()}'),
    title: p.title,
    body: p.body,
    payload: payload.encode(),
    scheduledDate: tz.TZDateTime.from(again, tz.UTC),
    notificationDetails: LocalNotificationsReminderScheduler.detailsFor(p.actions),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

/// Snooze pressed while the app isn't running (a separate isolate).
@pragma('vm:entry-point')
void onReminderButtonInBackground(NotificationResponse response) {
  if (response.actionId != ReminderAction.snooze) return;
  final plugin = FlutterLocalNotificationsPlugin();
  plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      )
      .then((_) => snoozeReminder(plugin, response))
      .ignore();
}

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return NoopReminderScheduler();
  }
  return LocalNotificationsReminderScheduler();
});
