import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/calendar_store.dart';
import '../data/event_actions.dart';
import '../data/linked_apps.dart';
import '../ics/ics.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../util/format.dart';
import 'event_editor_page.dart';
import 'linked_app_launcher.dart';
import 'linked_pickers.dart';

/// One event (or one occurrence of a series): when, where, who, notes.
class EventDetailsPage extends ConsumerWidget {
  const EventDetailsPage({super.key, required this.eventId, this.occurrenceStart});

  final String eventId;

  /// For a series, the occurrence that was tapped.
  final DateTime? occurrenceStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider).value;
    final event = events?.where((e) => e.id == eventId).firstOrNull;
    if (event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: events == null
              ? const CircularProgressIndicator()
              : const Text('This event was deleted.'),
        ),
      );
    }
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final calendar = calendars.firstWhere(
      (c) => c.id == event.calendarId,
      orElse: () => ZtCalendarInfo.personal,
    );
    final notes = ref.watch(linkedNotesProvider).value ?? const <LinkedNote>[];
    final contacts = ref.watch(linkedContactsProvider).value ?? const <LinkedContact>[];
    final theme = Theme.of(context);

    final occ = event.repeats ? (occurrenceStart ?? event.start) : event.start;
    final occEnd = event.allDay
        ? addDays(dayOf(occ), (event.duration.inHours / 24).round())
        : occ.add(event.duration);
    final color = Color(event.color ?? calendar.color);
    final guests = [
      for (final id in event.contactIds)
        if (contacts.where((c) => c.id == id).firstOrNull case final LinkedContact c) c,
    ];
    final guestEmails = [for (final g in guests) ...g.emails.take(1)];

    Future<void> edit() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => EventEditorPage(
          event: event,
          occurrenceStart: event.repeats ? occ : null,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: edit,
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref, event, occ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'duplicate':
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => EventEditorPage(
                        event: event.copyWith(
                          start: occ,
                          end: occEnd,
                          exceptions: const {},
                          seriesId: null,
                          originalStart: null,
                        ),
                        duplicate: true,
                      ),
                    ),
                  );
                case 'share':
                  await _share(event);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              PopupMenuItem(value: 'share', child: Text('Share as .ics file')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 24, left: 4),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        event.title.isEmpty ? '(No title)' : event.title,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.allDay
                            ? '${formatLongDay(occ)}'
                                  '${addDays(occEnd, -1).isAfter(occ) ? ' to ${formatLongDay(addDays(occEnd, -1))}' : ''}'
                            : sameDay(occ, occEnd)
                            ? '${formatLongDay(occ)}\n${formatSpan(context, occ, occEnd, false)}'
                            : formatSpan(context, occ, occEnd, false),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (event.repeats)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            describeRule(event.recurrence, event.start),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (event.location.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(event.location),
              subtitle: const Text('Open in maps'),
              onTap: () => _openLocation(event.location),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(calendar.name),
          ),
          for (final m in event.reminders)
            ListTile(
              leading: Icon(m == event.reminders.first ? Icons.notifications_outlined : null),
              title: Text(reminderLabel(m, allDay: event.allDay)),
            ),
          if (event.description.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: SelectableText(event.description),
            ),
          if (event.contactIds.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(
                '${event.contactIds.length} '
                '${event.contactIds.length == 1 ? 'guest' : 'guests'}',
              ),
              trailing: guestEmails.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Email guests',
                      icon: const Icon(Icons.email_outlined),
                      onPressed: () => launchUrl(
                        Uri(
                          scheme: 'mailto',
                          path: guestEmails.join(','),
                          query: 'subject=${Uri.encodeComponent(event.title)}',
                        ),
                      ),
                    ),
            ),
            for (final g in guests)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 8),
                title: Text(g.name),
                subtitle: g.emails.isEmpty ? null : Text(g.emails.first),
                trailing: g.phones.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Call ${g.name}',
                        icon: const Icon(Icons.call_outlined),
                        onPressed: () => launchUrl(Uri(scheme: 'tel', path: g.phones.first)),
                      ),
              ),
            if (guests.length < event.contactIds.length)
              const ListTile(
                contentPadding: EdgeInsets.only(left: 72, right: 8),
                title: Text('Some guests are no longer in ZT Contacts'),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: const Text('Notes'),
            trailing: TextButton.icon(
              onPressed: () async {
                final id = await pickNote(
                  context,
                  ref,
                  eventTitle: event.title,
                  eventStart: occ,
                  exclude: event.noteIds.toSet(),
                );
                if (id == null) return;
                await ref
                    .read(calendarRepositoryProvider)
                    .saveEvent(event.copyWith(noteIds: [...event.noteIds, id]));
              },
              icon: const Icon(Icons.add),
              label: const Text('Link'),
            ),
          ),
          for (final id in event.noteIds)
            Builder(
              builder: (context) {
                final note = notes.where((n) => n.id == id).firstOrNull;
                return ListTile(
                  contentPadding: const EdgeInsets.only(left: 72, right: 8),
                  title: Text(note?.displayTitle ?? 'Note not available yet'),
                  subtitle: note == null
                      ? const Text('Still syncing, or deleted in ZT Notes')
                      : note.body.trim().isEmpty
                      ? null
                      : Text(note.body.trim(), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: note == null ? null : () => showNoteSheet(context, note),
                  trailing: IconButton(
                    tooltip: 'Unlink note',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => ref
                        .read(calendarRepositoryProvider)
                        .saveEvent(
                          event.copyWith(
                            noteIds: [...event.noteIds]..remove(id),
                          ),
                        ),
                  ),
                );
              },
            ),
          if (event.noteIds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 72, right: 16),
              child: Text(
                'Link meeting notes, an agenda or a packing list from ZT Notes.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openLocation(String location) async {
    final trimmed = location.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!await launchUrl(mapsUri(trimmed))) {
      await launchUrl(
        Uri.https('www.openstreetmap.org', '/search', {'query': trimmed}),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _share(CalendarEvent event) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/event.ics');
    await file.writeAsString(Ics.write([event], name: event.title));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/calendar')]),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CalendarEvent event,
    DateTime occ,
  ) async {
    final repo = ref.read(calendarRepositoryProvider);
    if (event.repeats) {
      final scope = await askSeriesScope(context, action: 'Delete');
      if (scope == null) return;
      await repo.apply(
        SeriesEdits.delete(
          series: event,
          occurrence: occ,
          scope: scope,
          exceptions: await repo.exceptionsOf(event.id),
        ),
      );
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Delete this event?'),
          content: const Text('It is deleted on all your devices.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
      await repo.deleteEvent(event.id);
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
