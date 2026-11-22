import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

import '../data/subscriptions.dart';
import '../data/time_links.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';

/// One occurrence of an event that ZT Keyboard can type something of.
@immutable
class PickOccurrence {
  const PickOccurrence(this.event, this.start, this.end);
  final CalendarEvent event;
  final DateTime start;
  final DateTime end;
}

/// How far ahead events are offered.
const pickDaysAhead = 30;

/// What is offered: every occurrence from today through the next
/// [pickDaysAhead] days, soonest first. With a [query], instead every event
/// whose title or place holds it, at its next occurrence (or its own time
/// when it is over), upcoming first.
List<PickOccurrence> pickOccurrences(List<CalendarEvent> events, DateTime now, String query) {
  final today = dayOf(now);
  final q = query.trim().toLowerCase();
  final out = <PickOccurrence>[];
  if (q.isEmpty) {
    final to = addDays(today, pickDaysAhead);
    for (final e in events) {
      for (final (s, end) in e.occurrencesBetween(today, to)) {
        out.add(PickOccurrence(e, s, end));
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
  for (final e in events) {
    if (!(e.title.toLowerCase().contains(q) || e.location.toLowerCase().contains(q))) continue;
    final start = e.repeats ? (e.nextStart(today) ?? e.start) : e.start;
    final end = e.allDay
        ? addDays(dayOf(start), (e.duration.inHours / 24).round())
        : start.add(e.duration);
    out.add(PickOccurrence(e, start, end));
  }
  out.sort((a, b) {
    final aPast = a.end.isBefore(now);
    final bPast = b.end.isBefore(now);
    if (aPast != bPast) return aPast ? 1 : -1;
    return aPast ? b.start.compareTo(a.start) : a.start.compareTo(b.start);
  });
  return out;
}

/// "Tuesday, November 24, 2026, 10:00 to 11:00"; only the day(s) for an
/// all-day event.
String pickWhen(BuildContext context, PickOccurrence o) {
  if (o.event.allDay) {
    final last = addDays(o.end, -1);
    return last.isAfter(o.start)
        ? context.l10n.spanTo(formatLongDay(o.start), formatLongDay(last))
        : formatLongDay(o.start);
  }
  if (sameDay(o.start, o.end) || o.end == addDays(dayOf(o.start), 1)) {
    return '${formatLongDay(o.start)}, ${formatSpan(context, o.start, o.end, false)}';
  }
  return formatSpan(context, o.start, o.end, false);
}

/// Opened by ZT Keyboard's "Insert from ZT apps" key, once the vault is
/// unlocked: the user taps a date, or an event and then what to type of it.
/// Pops with that text, or with nothing when the user goes back.
class PickForKeyboardPage extends ConsumerStatefulWidget {
  const PickForKeyboardPage({super.key, this.now, this.wantItem = false});

  /// For tests; the current time otherwise.
  final DateTime? now;

  /// ZT Time asked for an event: tapping one answers at once with a
  /// [PickedItem] (its title as the text), instead of asking what to type.
  final bool wantItem;

  @override
  ConsumerState<PickForKeyboardPage> createState() => _PickForKeyboardPageState();
}

class _PickForKeyboardPageState extends ConsumerState<PickForKeyboardPage> {
  String _query = '';

  DateTime get _now => widget.now ?? DateTime.now();

  void _send(String text) => Navigator.of(context).pop(text);

  Future<void> _anotherDate() async {
    final today = dayOf(_now);
    final day = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 100),
      lastDate: DateTime(today.year + 100),
    );
    if (day != null && mounted) _send(formatLongDay(day));
  }

  Future<void> _open(PickOccurrence o) async {
    if (widget.wantItem) {
      final title = o.event.title.trim().isEmpty ? context.l10n.noTitle : o.event.title.trim();
      Navigator.of(context).pop(
        PickedItem(
          text: title,
          id: timeItemId(o.event, o.start),
          title: title,
          start: o.event.allDay ? null : o.start,
          end: o.event.allDay ? null : o.end,
        ),
      );
      return;
    }
    final l10n = context.l10n;
    final e = o.event;
    final values = <(IconData, String, String)>[
      if (e.title.trim().isNotEmpty) (Icons.title, l10n.insertEventTitle, e.title.trim()),
      (Icons.schedule, l10n.insertEventWhen, pickWhen(context, o)),
      (Icons.event, l10n.insertEventDate, formatLongDay(o.start)),
      if (e.location.trim().isNotEmpty)
        (Icons.place_outlined, l10n.insertEventPlace, e.location.trim()),
      if ((e.conferenceUrl ?? '').trim().isNotEmpty)
        (Icons.videocam_outlined, l10n.insertEventLink, e.conferenceUrl!.trim()),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (icon, label, text) in values)
                ListTile(
                  leading: Icon(icon),
                  title: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(label),
                  onTap: () => Navigator.of(sheet).pop(text),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) _send(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final now = _now;
    final today = dayOf(now);
    final tomorrow = addDays(today, 1);
    final events = ref.watch(allEventsProvider).value ?? const <CalendarEvent>[];
    final found = pickOccurrences(events, now, _query);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.insertIntoKeyboard)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchEvents,
                helperText: l10n.insertPickHint,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_query.trim().isEmpty) ...[
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(l10n.today),
              subtitle: Text(formatLongDay(today)),
              onTap: () => _send(formatLongDay(today)),
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: Text(l10n.tomorrow),
              subtitle: Text(formatLongDay(tomorrow)),
              onTap: () => _send(formatLongDay(tomorrow)),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(l10n.insertAnotherDate),
              onTap: _anotherDate,
            ),
            const Divider(),
          ],
          if (found.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(_query.trim().isEmpty ? l10n.insertNoEvents : l10n.noEventsFound),
              ),
            ),
          for (final o in found)
            ListTile(
              title: Text(
                o.event.title.trim().isEmpty ? l10n.noTitle : o.event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(pickWhen(context, o), maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _open(o),
            ),
        ],
      ),
    );
  }
}
