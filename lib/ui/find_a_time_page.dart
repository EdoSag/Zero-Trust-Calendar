import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/find_a_time.dart';
import '../data/shared_calendars.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';
import 'event_editor_page.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Slots when every member who shares their busy times is free, and the
/// shared calendar itself has nothing on. Tapping one opens a new event in
/// the shared calendar at that time.
class FindATimePage extends ConsumerStatefulWidget {
  const FindATimePage({super.key, required this.spaceId});
  final String spaceId;

  @override
  ConsumerState<FindATimePage> createState() => _FindATimePageState();
}

class _FindATimePageState extends ConsumerState<FindATimePage> {
  Duration _length = const Duration(hours: 1);
  bool _evenings = false;
  bool _weekends = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final shared = (ref.watch(sharedCalendarsProvider).value ?? const [])
        .where((c) => c.spaceId == widget.spaceId)
        .firstOrNull;
    if (shared == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.sharedCalendarGone)),
      );
    }
    final now = DateTime.now();
    final members = {for (final m in shared.members) m.userId: m.name};
    final sharing = [
      for (final b in shared.busy)
        if (members.containsKey(b.userId)) b,
    ];
    final from = dayOf(now);
    final busy = [
      for (final b in sharing) ...b.blocks,
      for (final e in shared.events)
        if (!e.allDay) ...e.occurrencesBetween(from, addDays(from, 15)),
    ];
    final slots = freeSlots(
      busy: busy,
      from: from,
      now: now,
      length: _length,
      dayStartHour: 8,
      dayEndHour: _evenings ? 22 : 18,
      weekends: _weekends,
    );
    final byDay = <DateTime, List<DateTime>>{};
    for (final s in slots) {
      (byDay[dayOf(s)] ??= []).add(s);
    }
    final missing = [
      for (final MapEntry(:key, :value) in members.entries)
        if (!sharing.any((b) => b.userId == key)) value,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.findATime)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in const [
                  Duration(minutes: 30),
                  Duration(hours: 1),
                  Duration(hours: 2),
                ])
                  ChoiceChip(
                    label: Text(l.findATimeLength(d.inMinutes)),
                    selected: _length == d,
                    onSelected: (_) => setState(() => _length = d),
                  ),
                FilterChip(
                  label: Text(l.findATimeEvenings),
                  selected: _evenings,
                  onSelected: (v) => setState(() => _evenings = v),
                ),
                FilterChip(
                  label: Text(l.findATimeWeekends),
                  selected: _weekends,
                  onSelected: (v) => setState(() => _weekends = v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              missing.isEmpty
                  ? l.findATimeEveryone
                  : l.findATimeMissing(missing.join(', ')),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (slots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.findATimeNone, textAlign: TextAlign.center),
            ),
          for (final MapEntry(key: day, value: times) in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                relativeDay(day, now: now),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in times)
                    ActionChip(
                      label: Text(formatTime(context, t)),
                      onPressed: () => _create(shared, t),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _create(SharedCalendar shared, DateTime start) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EventEditorPage(
          draft: CalendarEvent(
            id: '',
            title: '',
            start: start,
            end: start.add(_length),
            calendarId: shared.id,
          ),
        ),
      ),
    );
  }
}
