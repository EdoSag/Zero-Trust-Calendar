import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../model/calendar_event.dart';

/// One reminder the OS should show at [at], for one occurrence of an event.
@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.eventId,
    required this.occurrence,
    required this.at,
    required this.title,
    required this.body,
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

  /// Carried on the notification so a tap can open the event.
  String get payload => '$eventId|${occurrence.toUtc().toIso8601String()}';

  static (String, DateTime?)? parsePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = payload.split('|');
    return (
      parts.first,
      parts.length > 1 ? DateTime.tryParse(parts[1])?.toLocal() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.notificationId == notificationId &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(notificationId, title, body);
}

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
    final starts = e.repeats
        ? e.recurrence!.between(e.start, from, to, exclude: e.exceptions)
        : (e.start.isBefore(to) && !e.start.isBefore(from) ? [e.start] : <DateTime>[]);
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
              title: showTitles && title.isNotEmpty ? title : 'Event',
              body: bodyFor(e, s),
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

  /// (event id, occurrence start) from reminder taps, including the one
  /// that launched the app.
  Stream<(String, DateTime?)> get taps;
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
  Stream<(String, DateTime?)> get taps => const Stream.empty();
}

class LocalNotificationsReminderScheduler implements ReminderScheduler {
  LocalNotificationsReminderScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final _taps = StreamController<(String, DateTime?)>.broadcast();
  (String, DateTime?)? _launch;
  Future<void>? _ready;

  static const _channel = AndroidNotificationDetails(
    'event_reminders',
    'Event reminders',
    channelDescription: 'Reminders before your events',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.event,
    // The lock screen shows "ZT Calendar", not the event's title.
    visibility: NotificationVisibility.private,
  );

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

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
        final tap = ScheduledReminder.parsePayload(response.payload);
        if (tap != null) _taps.add(tap);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launch = ScheduledReminder.parsePayload(
        launch!.notificationResponse?.payload,
      );
    }
  }();

  Future<void> initialize() => _init();

  @override
  Stream<(String, DateTime?)> get taps async* {
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
      final want = wanted[request.id];
      if (want == null) {
        await _plugin.cancel(id: request.id);
      } else if (request.title == want.title && request.body == want.body) {
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
        notificationDetails: _details,
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

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return NoopReminderScheduler();
  }
  return LocalNotificationsReminderScheduler();
});
