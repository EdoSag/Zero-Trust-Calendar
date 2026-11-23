import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/calendar_event.dart';

/// Links with ZT Time (the suite's "ZT Time links" protocol, TM-2 / TM-5):
/// "Log as time entry" on an event, ZT Time opening a linked event, and
/// ZT Time asking the picker for an event.
///
/// The id ZT Time keeps for an event: the event's own id, and for one
/// occurrence of a repeating event also its start (`id|UTC start`).
String timeItemId(CalendarEvent event, DateTime occurrenceStart) =>
    event.repeats ? '${event.id}|${occurrenceStart.toUtc().toIso8601String()}' : event.id;

/// Reads back [timeItemId]: the event id and, for an occurrence, its start.
({String eventId, DateTime? occurrence}) parseTimeItemId(String itemId) {
  final bar = itemId.indexOf('|');
  if (bar < 0) return (eventId: itemId, occurrence: null);
  return (
    eventId: itemId.substring(0, bar),
    occurrence: DateTime.tryParse(itemId.substring(bar + 1))?.toLocal(),
  );
}

/// An event picked for ZT Time, sent with the picked text.
@immutable
class PickedItem {
  const PickedItem({required this.text, required this.id, required this.title, this.start, this.end});
  final String text;
  final String id;
  final String title;
  final DateTime? start;
  final DateTime? end;

  Map<String, Object?> toChannel() => {
    'id': id,
    'title': title,
    if (start != null) 'startMs': start!.millisecondsSinceEpoch,
    if (end != null) 'endMs': end!.millisecondsSinceEpoch,
  };
}

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// ZT Time on this phone.
class TimeLink {
  const TimeLink();
  static const _channel = MethodChannel('zt_calendar/apps');

  /// Installed and signed with the suite's key.
  Future<bool> installed() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('timeInstalled') ?? false;
    } on Object {
      return false;
    }
  }

  /// Opens ZT Time's "Add time" for an occurrence of [event]: filled in
  /// with its title and times (none for an all-day event, so Time offers a
  /// timer). True once saved there, false when cancelled, null when ZT Time
  /// couldn't be opened.
  Future<bool?> logTime(CalendarEvent event, DateTime start, DateTime end) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<bool>('trackTime', {
        'id': timeItemId(event, start),
        'title': event.title,
        if (!event.allDay) 'startMs': start.millisecondsSinceEpoch,
        if (!event.allDay) 'endMs': end.millisecondsSinceEpoch,
      });
    } on Object {
      return null;
    }
  }
}

final timeLinkProvider = Provider<TimeLink>((ref) => const TimeLink());

/// Whether "Log as time entry" is offered.
final timeInstalledProvider = FutureProvider<bool>((ref) => ref.watch(timeLinkProvider).installed());
