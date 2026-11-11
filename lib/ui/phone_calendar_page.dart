import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../model/calendar_event.dart';
import '../platform/channels.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

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
    final userId = ref.read(accountServiceProvider).currentUserId;
    final enabled = settings.phoneCalendarIdsFor(userId);

    Future<void> toggle(ZtCalendarInfo c, bool on) async {
      final messenger = ScaffoldMessenger.of(context);
      if (on) {
        final first = enabled.isEmpty;
        if (first) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(context.l10n.showOnThisPhone),
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
                TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(context.l10n.cancel)),
                FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(context.l10n.turnOn)),
              ],
            ),
          );
          if (ok != true) return;
        }
        if (!await bridge.requestPermission()) {
          messenger.showSnackBar(
            SnackBar(content: Text(currentL10n.calendarPermissionIsNeededFor)),
          );
          return;
        }
      }
      await ref.read(calendarSettingsProvider.notifier).update(
        (s) {
          final current = s.phoneCalendarIdsFor(userId);
          return s.copyWith(
            phoneCalendarOwner: userId,
            phoneCalendarIds: on ? {...current, c.id} : ({...current}..remove(c.id)),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.showOnThisPhoneX)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              context.l10n.letsWearOsAndroidAuto,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (userId == null)
            ListTile(title: Text(context.l10n.signInFirst))
          else if (!bridge.supported)
            ListTile(title: Text(context.l10n.onlyAvailableOnAndroid))
          else
            for (final c in calendars)
              SwitchListTile(
                secondary: Icon(Icons.circle, color: Color(c.color)),
                title: Text(c.name),
                value: enabled.contains(c.id),
                onChanged: (v) => toggle(c, v),
              ),
        ],
      ),
    );
  }
}
