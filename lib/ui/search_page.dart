import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_store.dart';
import '../data/entries.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'navigation.dart';

/// Searches titles, places and descriptions, on this device only.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsProvider).value ?? const <CalendarEvent>[];
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final byId = {for (final c in calendars) c.id: c};
    final q = _query.toLowerCase();
    final now = DateTime.now();
    final results = <CalendarEntry>[];
    if (q.isNotEmpty) {
      for (final e in events) {
        if (!(e.title.toLowerCase().contains(q) ||
            e.location.toLowerCase().contains(q) ||
            e.description.toLowerCase().contains(q))) {
          continue;
        }
        // A series shows at its next occurrence, or its first.
        final start = e.repeats ? (e.nextStart(dayOf(now)) ?? e.start) : e.start;
        final end = e.allDay
            ? addDays(dayOf(start), (e.duration.inHours / 24).round())
            : start.add(e.duration);
        results.add(
          CalendarEntry(
            kind: EntryKind.event,
            title: e.title.isEmpty ? '(No title)' : e.title,
            start: start,
            end: end,
            allDay: e.allDay,
            color: e.color ?? (byId[e.calendarId] ?? ZtCalendarInfo.personal).color,
            event: e,
          ),
        );
      }
      // Upcoming first (soonest), then past (most recent).
      results.sort((a, b) {
        final aPast = a.end.isBefore(now);
        final bPast = b.end.isBefore(now);
        if (aPast != bPast) return aPast ? 1 : -1;
        return aPast ? b.start.compareTo(a.start) : a.start.compareTo(b.start);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search events',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      body: q.isEmpty
          ? const SizedBox.shrink()
          : results.isEmpty
          ? const Center(child: Text('No events found'))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, i) {
                final e = results[i];
                final header = i == 0 || !sameDay(results[i - 1].start, e.start);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (header)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                        child: Text(
                          relativeDay(e.start),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    EntryTile(entry: e, onTap: () => openEntry(context, ref, e)),
                  ],
                );
              },
            ),
    );
  }
}
