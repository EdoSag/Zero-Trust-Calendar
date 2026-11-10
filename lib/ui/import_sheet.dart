import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/calendar_store.dart';
import '../ics/ics.dart';
import '../ics/import_service.dart';
import '../model/calendar_event.dart';
import '../platform/channels.dart';
import '../util/format.dart';
import 'subscribe_page.dart';

/// Handles a file or link another app opened Calendar with: an .ics file
/// or invitation ("Add to ZT Calendar"), or a webcal:// subscribe link.
Future<void> handleIncomingFile(
  BuildContext context,
  WidgetRef ref,
  IncomingFile file,
) async {
  if (file.url != null) {
    await showSubscribeDialog(context, ref, url: file.url);
    return;
  }
  final bytes = file.bytes;
  if (bytes == null) return;
  final text = utf8.decode(bytes, allowMalformed: true);
  final parsed = Ics.parse(text);
  if (!context.mounted) return;
  if (parsed.events.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No events in that file.')),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AddFileSheet(name: file.name ?? 'event.ics', bytes: bytes, parsed: parsed),
  );
}

class _AddFileSheet extends ConsumerStatefulWidget {
  const _AddFileSheet({required this.name, required this.bytes, required this.parsed});
  final String name;
  final Uint8List bytes;
  final IcsCalendar parsed;

  @override
  ConsumerState<_AddFileSheet> createState() => _AddFileSheetState();
}

class _AddFileSheetState extends ConsumerState<_AddFileSheet> {
  String _calendarId = CalendarEvent.defaultCalendarId;
  bool _busy = false;

  bool get _cancel => widget.parsed.method == 'CANCEL';
  bool get _invite => widget.parsed.method == 'REQUEST';

  /// Your events the file's UIDs match (an invitation you already added).
  List<CalendarEvent> _matches(List<CalendarEvent> mine) {
    final uids = {for (final e in widget.parsed.events) if (e.icalUid != null) e.icalUid};
    return [for (final e in mine) if (e.icalUid != null && uids.contains(e.icalUid) && e.seriesId == null) e];
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(calendarRepositoryProvider);
    try {
      final mine = await repo.allEvents();
      final matches = _matches(mine);
      if (_cancel) {
        for (final e in matches) {
          await repo.deleteSeries(e);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('Removed ${matches.length} cancelled ${matches.length == 1 ? 'event' : 'events'}')),
        );
      } else if (_invite && matches.isNotEmpty) {
        // An updated invitation: new time and details, your own reminders,
        // notes and calendar kept.
        for (final old in matches) {
          final fresh = widget.parsed.events.firstWhere((e) => e.icalUid == old.icalUid);
          await repo.saveEvent(
            old.copyWith(
              title: fresh.title,
              start: fresh.start,
              end: fresh.end,
              allDay: fresh.allDay,
              location: fresh.location,
              description: fresh.description,
              rrule: fresh.rrule,
              exceptions: fresh.exceptions,
              timeZone: fresh.timeZone,
              conferenceUrl: fresh.conferenceUrl,
            ),
          );
        }
        messenger.showSnackBar(const SnackBar(content: Text('Event updated')));
      } else {
        final plan = IcsImportPlan.build(
          files: [(widget.name.toLowerCase().endsWith('.zip') ? widget.name : 'event.ics', widget.bytes)],
          existing: mine,
          calendars: await ref.read(calendarsProvider.future),
          intoCalendarId: _calendarId,
        );
        for (final e in [...plan.updatedSeries, ...plan.events]) {
          await repo.saveEvent(e);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              plan.events.isEmpty
                  ? 'Already in your calendar'
                  : 'Added ${plan.events.length} ${plan.events.length == 1 ? 'event' : 'events'}',
            ),
          ),
        );
      }
      navigator.pop();
    } on Object catch (e) {
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not add it: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = widget.parsed.events.where((e) => e.seriesId == null).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final calendars = [
      for (final c in ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal])
        if (!c.isSubscription) c,
    ];
    final mine = ref.watch(eventsProvider).value ?? const <CalendarEvent>[];
    final matches = _matches(mine);
    final title = _cancel
        ? 'Cancelled event'
        : _invite
        ? (matches.isEmpty ? 'Invitation' : 'Updated invitation')
        : 'Add to ZT Calendar';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final e in events.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(e.title.isEmpty ? '(No title)' : e.title),
                subtitle: Text(
                  [
                    e.allDay
                        ? formatLongDay(e.start)
                        : '${formatLongDay(e.start)}, ${formatSpan(context, e.start, e.end, false)}',
                    if (e.repeats) describeRule(e.recurrence, e.start),
                    if (e.location.isNotEmpty) e.location,
                  ].join('\n'),
                ),
              ),
            if (events.length > 5)
              Text('and ${events.length - 5} more', style: theme.textTheme.bodySmall),
            if (_cancel)
              Text(
                matches.isEmpty
                    ? 'It isn\'t in your calendar.'
                    : 'The organizer cancelled it. Remove it from your calendar?',
              )
            else if (!(_invite && matches.isNotEmpty) && calendars.length > 1)
              DropdownButtonFormField<String>(
                initialValue: _calendarId,
                decoration: const InputDecoration(labelText: 'Calendar'),
                items: [
                  for (final c in calendars)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 14, color: Color(c.color)),
                          const SizedBox(width: 8),
                          Text(c.name),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _calendarId = v ?? _calendarId),
              ),
            if (_invite)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'To reply, answer the organizer from your mail app.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy || (_cancel && matches.isEmpty) ? null : _apply,
                  child: Text(
                    _cancel
                        ? 'Remove'
                        : _invite && matches.isNotEmpty
                        ? 'Update'
                        : 'Add',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
