import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../model/calendar_event.dart';
import '../platform/channels.dart';

/// "Show on this phone": per calendar, copy its events into Android's
/// calendar so the clock, Wear OS, Android Auto and other apps show them.
/// Off by default, per phone.
class PhoneCalendarPage extends ConsumerWidget {
  const PhoneCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(calendarSettingsProvider);
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final theme = Theme.of(context);
    const bridge = PhoneCalendarBridge();

    Future<void> toggle(ZtCalendarInfo c, bool on) async {
      final messenger = ScaffoldMessenger.of(context);
      if (on) {
        final first = settings.phoneCalendarIds.isEmpty;
        if (first) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Show on this phone?'),
              content: const Text(
                'Events in this calendar are copied, unencrypted, into '
                'Android\'s calendar on this phone: title, time and place, '
                'from a month ago to a year ahead. Your watch, car, clock and '
                'any app you allow to read calendars can then see them.\n\n'
                'They stay on this phone (a local calendar Android doesn\'t '
                'sync), and turning this off removes them. Descriptions, '
                'guests, notes and attachments are never copied.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Turn on')),
              ],
            ),
          );
          if (ok != true) return;
        }
        if (!await bridge.requestPermission()) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Calendar permission is needed for this.')),
          );
          return;
        }
      }
      await ref.read(calendarSettingsProvider.notifier).update(
        (s) => s.copyWith(
          phoneCalendarIds: on
              ? {...s.phoneCalendarIds, c.id}
              : ({...s.phoneCalendarIds}..remove(c.id)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Show on this phone')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Lets Wear OS, Android Auto, the clock\'s alarm screen and other '
              'calendar apps show these events. They are copied without '
              'encryption into a calendar on this phone only.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (!bridge.supported)
            const ListTile(title: Text('Only available on Android.'))
          else
            for (final c in calendars)
              SwitchListTile(
                secondary: Icon(Icons.circle, color: Color(c.color)),
                title: Text(c.name),
                value: settings.phoneCalendarIds.contains(c.id),
                onChanged: (v) => toggle(c, v),
              ),
        ],
      ),
    );
  }
}
