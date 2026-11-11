import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/calendar_store.dart';
import '../data/shared_calendars.dart';
import '../data/subscriptions.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';
import 'shared_calendar_pages.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

/// Add, rename, recolour, hide and delete calendars.
class CalendarsPage extends ConsumerWidget {
  const CalendarsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final events = ref.watch(allEventsProvider).value ?? const <CalendarEvent>[];
    final shared = ref.watch(sharedCalendarsProvider).value ?? const <SharedCalendar>[];
    final joins = ref.watch(pendingJoinsProvider).value ?? const [];
    final waiting = [for (final s in shared) if (s.waiting) s];
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.calendars)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewCalendarChoices(
          context,
          ref,
          newCalendar: () => _edit(context, ref, null, calendars.length),
        ),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.newCalendar),
      ),
      body: ListView(
        children: [
          for (final c in calendars)
            ListTile(
              leading: Icon(
                c.isSubscription
                    ? Icons.rss_feed
                    : c.isShared
                    ? (shared.any((s) => s.id == c.id && s.family) ? Icons.family_restroom : Icons.group)
                    : Icons.circle,
                color: Color(c.color),
              ),
              title: Text(c.name),
              subtitle: Text(() {
                final n = events.where((e) => e.calendarId == c.id && e.seriesId == null).length;
                final s = shared.where((s) => s.id == c.id).firstOrNull;
                final asking = joins.where((j) => j.spaceId == s?.spaceId).length;
                return '${context.l10n.nEvents(n)}'
                    '${s != null ? ' · ${context.l10n.nMembers(s.members.length)}' : ''}'
                    '${asking > 0 ? ' · ${context.l10n.nWaitingToJoin(asking)}' : ''}'
                    '${c.isSubscription ? ' · ${context.l10n.subscribedReadOnly}' : ''}'
                    '${c.hidden ? ' · ${context.l10n.hiddenLabel}' : ''}';
              }()),
              trailing: Icon(c.isShared ? Icons.chevron_right : Icons.edit_outlined),
              onTap: () => c.isShared
                  ? Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SharedCalendarPage(spaceId: spaceIdOf(c.id)!),
                      ),
                    )
                  : _edit(context, ref, c, calendars.length),
            ),
          for (final s in waiting)
            ListTile(
              leading: const Icon(Icons.hourglass_top),
              title: Text(context.l10n.waitingToJoin),
              subtitle: Text(context.l10n.waitingToJoinShort),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SharedCalendarPage(spaceId: s.spaceId),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              context.l10n.calendarsLikeEventsAreEnd,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ZtCalendarInfo? calendar,
    int count,
  ) async {
    final name = TextEditingController(text: calendar?.name ?? '');
    var color = calendar?.color ?? calendarPalette[count % calendarPalette.length];
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text(calendar == null ? context.l10n.newCalendar : context.l10n.editCalendar),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: calendar == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: context.l10n.name),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in calendarPalette)
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => color = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                          child: c == color
                              ? Icon(Icons.check, size: 18, color: onColor(Color(c)))
                              : null,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (calendar != null && calendar.id != CalendarEvent.defaultCalendarId)
              TextButton(
                onPressed: () => Navigator.of(dialog).pop('delete'),
                child: Text(context.l10n.delete),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop('save'),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    final repo = ref.read(calendarRepositoryProvider);
    if (result == 'save') {
      final trimmed = name.text.trim();
      await repo.saveCalendar(
        (calendar ??
                ZtCalendarInfo(id: const Uuid().v4(), name: '', color: color))
            .copyWith(name: trimmed.isEmpty ? currentL10n.calendarDefaultName : trimmed, color: color),
      );
    } else if (result == 'delete' && calendar != null && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(
            calendar.isSubscription ? context.l10n.unsubscribeFrom(calendar.name) : context.l10n.deleteNamed(calendar.name),
          ),
          content: Text(
            calendar.isSubscription
                ? context.l10n.itsEventsDisappearFromAll
                : context.l10n.itsEventsAreDeletedToo,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.delete)),
          ],
        ),
      );
      if (ok == true) await repo.deleteCalendar(calendar.id);
    }
    name.dispose();
  }
}
