import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/calendar_store.dart';
import '../ics/ics.dart';
import '../ics/import_service.dart';
import '../model/calendar_event.dart';
import '../platform/channels.dart';
import '../util/format.dart';
import 'subscribe_page.dart';
import 'inline_button_style.dart';

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
  if (parsed.events.isEmpty && parsed.cancelled.isEmpty) {
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

  IcsCalendar get _p => widget.parsed;

  /// A cancellation: METHOD:CANCEL, or a file holding only cancelled events.
  bool get _cancel => _p.method == 'CANCEL' || (_p.events.isEmpty && _p.cancelled.isNotEmpty);
  bool get _invite => _p.method == 'REQUEST';

  /// What a cancellation removes: whole events, or single occurrences.
  List<({String uid, DateTime? occurrence})> get _cancelTargets => [
    ..._p.cancelled,
    if (_p.method == 'CANCEL')
      for (final e in _p.events)
        if (e.icalUid != null && e.seriesId == null)
          (uid: e.icalUid!, occurrence: _p.changedOccurrences[e.id]?.occurrence),
  ];

  /// Your stored event (or series) with [uid].
  static CalendarEvent? _stored(List<CalendarEvent> mine, String uid) =>
      mine.where((e) => e.icalUid == uid && e.seriesId == null).firstOrNull;

  static bool _same(DateTime a, DateTime b) => a.isAtSameMomentAs(b);

  /// The incoming events that match something you already have.
  int _matchCount(List<CalendarEvent> mine) {
    if (_cancel) {
      return _cancelTargets.where((t) => _stored(mine, t.uid) != null).length;
    }
    return [
      for (final e in _p.events)
        if (e.seriesId == null && e.icalUid != null)
          if (_stored(mine, _p.changedOccurrences[e.id]?.uid ?? e.icalUid!) != null) e,
    ].length;
  }

  /// Cancels one occurrence of [series]: skips the date and drops any
  /// changed copy of it you had.
  Future<void> _cancelOccurrence(
    CalendarRepository repo,
    List<CalendarEvent> mine,
    CalendarEvent series,
    DateTime occurrence,
  ) async {
    if (!series.exceptions.any((x) => _same(x, occurrence))) {
      await repo.saveEvent(series.copyWith(exceptions: {...series.exceptions, occurrence}));
    }
    for (final e in mine) {
      if (e.seriesId == series.id && e.originalStart != null && _same(e.originalStart!, occurrence)) {
        await repo.deleteEvent(e.id);
      }
    }
  }

  Future<int> _applyCancel(CalendarRepository repo, List<CalendarEvent> mine) async {
    var n = 0;
    for (final t in _cancelTargets) {
      final stored = _stored(mine, t.uid);
      if (stored == null) continue;
      n++;
      if (t.occurrence != null && stored.repeats) {
        await _cancelOccurrence(repo, mine, stored, t.occurrence!);
      } else {
        await repo.deleteSeries(stored);
      }
    }
    return n;
  }

  /// An updated invitation: new time and details; your reminders, notes,
  /// guests' replies and calendar kept. An update to one occurrence of a
  /// series becomes a changed occurrence, never a new master.
  Future<void> _applyUpdate(CalendarRepository repo, List<CalendarEvent> mine) async {
    for (final fresh in _p.events) {
      if (fresh.seriesId != null || fresh.icalUid == null) continue;
      final occ = _p.changedOccurrences[fresh.id];
      final stored = _stored(mine, occ?.uid ?? fresh.icalUid!);
      if (stored == null) continue;
      if (occ != null) {
        if (!stored.repeats) {
          // Your copy isn't a series: just move it.
          await repo.saveEvent(_updated(stored, fresh, keepRule: true));
          continue;
        }
        final existing = mine
            .where((e) => e.seriesId == stored.id && e.originalStart != null && _same(e.originalStart!, occ.occurrence))
            .firstOrNull;
        if (!stored.exceptions.any((x) => _same(x, occ.occurrence))) {
          await repo.saveEvent(stored.copyWith(exceptions: {...stored.exceptions, occ.occurrence}));
        }
        await repo.saveEvent(
          _updated(existing ?? stored, fresh, keepRule: false).copyWith(
            id: existing?.id ?? const Uuid().v4(),
            seriesId: stored.id,
            originalStart: occ.occurrence,
            rrule: null,
            exceptions: const <DateTime>{},
          ),
        );
      } else {
        await repo.saveEvent(_updated(stored, fresh, keepRule: false));
      }
    }
    // Occurrences the organizer cancelled inside the update.
    for (final t in _p.cancelled) {
      final stored = _stored(mine, t.uid);
      if (stored != null && t.occurrence != null && stored.repeats) {
        await _cancelOccurrence(repo, mine, stored, t.occurrence!);
      }
    }
  }

  static CalendarEvent _updated(CalendarEvent old, CalendarEvent fresh, {required bool keepRule}) =>
      old.copyWith(
        title: fresh.title,
        start: fresh.start,
        end: fresh.end,
        allDay: fresh.allDay,
        location: fresh.location,
        description: fresh.description,
        rrule: keepRule ? old.rrule : fresh.rrule,
        exceptions: keepRule ? old.exceptions : fresh.exceptions,
        timeZone: fresh.timeZone,
        conferenceUrl: fresh.conferenceUrl,
      );

  Future<void> _apply() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final repo = ref.read(calendarRepositoryProvider);
    try {
      final mine = await repo.allEvents();
      if (_cancel) {
        final n = await _applyCancel(repo, mine);
        messenger.showSnackBar(
          SnackBar(content: Text('Removed $n cancelled ${n == 1 ? 'event' : 'events'}')),
        );
      } else if (_invite && _matchCount(mine) > 0) {
        await _applyUpdate(repo, mine);
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
    final matched = _matchCount(mine);
    final title = _cancel
        ? 'Cancelled event'
        : _invite
        ? (matched == 0 ? 'Invitation' : 'Updated invitation')
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
                matched == 0
                    ? 'It isn\'t in your calendar.'
                    : 'The organizer cancelled it. Remove it from your calendar?',
              )
            else if (!(_invite && matched > 0) && calendars.length > 1)
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
                  style: inlineButtonStyle,
                  onPressed: _busy || (_cancel && matched == 0) ? null : _apply,
                  child: Text(
                    _cancel
                        ? 'Remove'
                        : _invite && matched > 0
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
