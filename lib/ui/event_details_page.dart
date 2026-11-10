import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/calendar_store.dart';
import '../data/event_actions.dart';
import '../data/linked_apps.dart';
import '../data/subscriptions.dart';
import '../ics/ics.dart';
import '../model/calendar_event.dart';
import '../model/linked_items.dart';
import '../util/format.dart';
import '../util/time_zones.dart';
import 'attachments.dart';
import 'event_editor_page.dart';
import 'guest_actions.dart';
import 'linked_app_launcher.dart';
import 'linked_pickers.dart';

/// One event (or one occurrence of a series): when, where, who, notes.
class EventDetailsPage extends ConsumerWidget {
  const EventDetailsPage({
    super.key,
    required this.eventId,
    this.occurrenceStart,
  });

  final String eventId;

  /// For a series, the occurrence that was tapped.
  final DateTime? occurrenceStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(allEventsProvider).value;
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
    final calendars =
        ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final calendar = calendars.firstWhere(
      (c) => c.id == event.calendarId,
      orElse: () => ZtCalendarInfo.personal,
    );
    final notes = ref.watch(linkedNotesProvider).value ?? const <LinkedNote>[];
    final contacts =
        ref.watch(linkedContactsProvider).value ?? const <LinkedContact>[];
    final theme = Theme.of(context);

    final occ = event.repeats ? (occurrenceStart ?? event.start) : event.start;
    final occEnd = event.allDay
        ? addDays(dayOf(occ), (event.duration.inHours / 24).round())
        : occ.add(event.duration);
    final color = Color(event.color ?? calendar.color);
    final guests = guestsOf(event, contacts);
    final guestEmails = [
      for (final g in guests)
        if (g.email != null) g.email!,
    ];
    final readOnly = event.readOnly;
    final zone = event.allDay ? null : zoneFor(event.timeZone);
    final call = event.conferenceUrl;

    Future<void> setRsvp(Guest g) async {
      final picked = await showDialog<String>(
        context: context,
        builder: (d) => SimpleDialog(
          title: Text(g.label),
          children: [
            for (final MapEntry(:key, :value) in rsvpLabels.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.of(d).pop(key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(value.$2),
                      const SizedBox(width: 16),
                      Text(value.$1),
                    ],
                  ),
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(d).pop(''),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('No reply yet'),
              ),
            ),
          ],
        ),
      );
      if (picked == null) return;
      final status = {...event.guestStatus}..remove(g.key);
      if (picked.isNotEmpty) status[g.key] = picked;
      await ref
          .read(calendarRepositoryProvider)
          .saveEvent(event.copyWith(guestStatus: status));
    }

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
          if (!readOnly)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: edit,
            ),
          if (!readOnly)
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
                          rrule: readOnly ? null : event.rrule,
                          calendarId: readOnly
                              ? CalendarEvent.defaultCalendarId
                              : null,
                          readOnly: false,
                          icalUid: null,
                          attachments: const [],
                          inviteSequence: 0,
                        ),
                        duplicate: true,
                      ),
                    ),
                  );
                case 'share':
                  await _share(event);
                case 'late':
                  if (context.mounted) {
                    await sendRunningLate(context, event, guests);
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'duplicate',
                child: Text(readOnly ? 'Copy to my calendar' : 'Duplicate'),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Text('Share as .ics file'),
              ),
              if (guests.isNotEmpty)
                const PopupMenuItem(value: 'late', child: Text('Running late')),
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
                      if (zone != null && differsFromPhone(zone, occ))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${formatSpan(context, wallClockIn(zone, occ), wallClockIn(zone, occEnd), false)} '
                            'in ${zoneCity(event.timeZone!)} (${utcOffsetLabel(zone, occ)})',
                            style: theme.textTheme.bodySmall,
                          ),
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
          if (call != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(call),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Join video call'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      Uri.tryParse(call)?.host ?? call,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
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
              onTap: () => openLocation(event.location),
            ),
          ListTile(
            leading: Icon(
              calendar.isSubscription
                  ? Icons.rss_feed
                  : Icons.calendar_today_outlined,
            ),
            title: Text(calendar.name),
            subtitle: calendar.isSubscription
                ? const Text('Subscribed calendar, read-only')
                : null,
          ),
          for (final m in event.reminders)
            ListTile(
              leading: Icon(
                m == event.reminders.first
                    ? Icons.notifications_outlined
                    : null,
              ),
              title: Text(reminderLabel(m, allDay: event.allDay)),
            ),
          if (event.description.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: SelectableText(event.description),
            ),
          if (event.attachments.isNotEmpty) ...[
            const Divider(),
            for (final a in event.attachments) AttachmentTile(attachment: a),
          ],
          if (event.contactIds.isNotEmpty || event.guestEmails.isNotEmpty) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(
                '${guests.length} ${guests.length == 1 ? 'guest' : 'guests'}',
              ),
              subtitle: () {
                final counts = <String, int>{};
                for (final g in guests) {
                  final st = event.guestStatus[g.key];
                  if (st != null) counts[st] = (counts[st] ?? 0) + 1;
                }
                if (counts.isEmpty) return null;
                return Text(
                  [
                    for (final MapEntry(:key, :value) in rsvpLabels.entries)
                      if (counts[key] case final n?)
                        '$n ${value.$1.toLowerCase()}',
                  ].join(', '),
                );
              }(),
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
                title: Text(g.label),
                subtitle: Text(
                  [
                    rsvpLabels[event.guestStatus[g.key]]?.$1 ?? 'No reply yet',
                    if (g.name != null && g.email != null) g.email!,
                  ].join(' · '),
                ),
                onTap: readOnly ? null : () => setRsvp(g),
                trailing: g.phone == null
                    ? null
                    : IconButton(
                        tooltip: 'Call ${g.label}',
                        icon: const Icon(Icons.call_outlined),
                        onPressed: () =>
                            launchUrl(Uri(scheme: 'tel', path: g.phone)),
                      ),
              ),
            if (!readOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          emailInvitation(context, ref, event, guests),
                      icon: const Icon(Icons.send_outlined),
                      label: Text(
                        event.inviteSequence == 0
                            ? 'Email invitation'
                            : 'Email update',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => sendRunningLate(context, event, guests),
                      icon: const Icon(Icons.directions_run),
                      label: const Text('Running late'),
                    ),
                  ],
                ),
              ),
            if (guests.length <
                event.contactIds.length + event.guestEmails.length)
              const ListTile(
                contentPadding: EdgeInsets.only(left: 72, right: 8),
                title: Text('Some guests are no longer in ZT Contacts'),
              ),
          ],
          if (!readOnly) ...[
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
                      .saveEvent(
                        event.copyWith(noteIds: [...event.noteIds, id]),
                      );
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
                        : Text(
                            note.body.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: note == null
                        ? null
                        : () => showNoteSheet(context, note),
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
        ],
      ),
    );
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
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await repo.deleteEvent(event.id);
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
