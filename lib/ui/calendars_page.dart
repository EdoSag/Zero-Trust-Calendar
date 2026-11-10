import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/calendar_store.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';

/// Add, rename, recolour, hide and delete calendars.
class CalendarsPage extends ConsumerWidget {
  const CalendarsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final events = ref.watch(eventsProvider).value ?? const <CalendarEvent>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Calendars')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null, calendars.length),
        icon: const Icon(Icons.add),
        label: const Text('New calendar'),
      ),
      body: ListView(
        children: [
          for (final c in calendars)
            ListTile(
              leading: Icon(Icons.circle, color: Color(c.color)),
              title: Text(c.name),
              subtitle: Text(() {
                final n = events.where((e) => e.calendarId == c.id && e.seriesId == null).length;
                return '$n ${n == 1 ? 'event' : 'events'}${c.hidden ? ' · hidden' : ''}';
              }()),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, ref, c, calendars.length),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Calendars, like events, are end-to-end encrypted and sync to '
              'your other devices.',
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
          title: Text(calendar == null ? 'New calendar' : 'Edit calendar'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: calendar == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
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
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialog).pop('save'),
              child: const Text('Save'),
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
            .copyWith(name: trimmed.isEmpty ? 'Calendar' : trimmed, color: color),
      );
    } else if (result == 'delete' && calendar != null && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Delete "${calendar.name}"?'),
          content: const Text(
            'Its events are deleted too, on all your devices. This can\'t be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) await repo.deleteCalendar(calendar.id);
    }
    name.dispose();
  }
}
