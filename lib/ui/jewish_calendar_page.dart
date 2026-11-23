import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/calendar_settings.dart';
import '../data/entries.dart';
import '../jewish/hebrew_date.dart';
import '../jewish/zmanim.dart';
import '../util/format.dart';
import 'entry_widgets.dart';
import 'package:zerotrust_calendar/l10n/l10n.dart';

bool _hebrew(BuildContext context) => Localizations.localeOf(context).languageCode == 'he';

/// "ג׳ כסלו תשפ״ז" or "3 Kislev 5787" for [day], in the app's language.
String hebrewDateLabel(BuildContext context, DateTime day, {bool withYear = true}) =>
    formatHebrewDate(HebrewDate.of(day), hebrew: _hebrew(context), withYear: withYear);

/// The Hebrew day for a small cell: the day alone, with the month on the
/// first of a Hebrew month.
String hebrewCellLabel(BuildContext context, DateTime day) {
  final h = HebrewDate.of(day);
  final hebrew = _hebrew(context);
  return h.day == 1
      ? '${formatHebrewDay(h, hebrew: hebrew)} ${hebrewMonthName(h.month, h.year, hebrew: hebrew)}'
      : formatHebrewDay(h, hebrew: hebrew);
}

/// A tap on a holiday, candle lighting or Havdalah entry.
Future<void> showJewishEntry(BuildContext context, CalendarEntry entry) {
  final mark = entry.jewish;
  final city = mark?.city;
  final hebrew = _hebrew(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(entryIcon(entry), color: Color(entry.color)),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.title, style: Theme.of(sheet).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              [
                formatLongDay(entry.start),
                if (!entry.allDay) formatTime(sheet, entry.start),
              ].join(', '),
            ),
            Text(hebrewDateLabel(sheet, entry.start)),
            if (city != null) ...[
              const SizedBox(height: 12),
              Text(
                sheet.l10n.jewishTimesAt(city.name(hebrew: hebrew), city.candleMinutes),
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Settings > Jewish calendar (K-1): Hebrew dates, holidays, and candle
/// lighting and Havdalah for a city. Everything is worked out on the
/// phone; nothing is fetched and no location is used.
class JewishCalendarPage extends ConsumerWidget {
  const JewishCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(calendarSettingsProvider);
    final ctrl = ref.read(calendarSettingsProvider.notifier);
    final l = context.l10n;
    final hebrew = _hebrew(context);
    final city = zmanimCity(s.shabbatCity);
    final israel = city?.israel ?? hebrew;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(l.jewishCalendar)),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.translate),
            title: Text(l.hebrewDates),
            subtitle: Text('${l.hebrewDatesHint} · ${hebrewDateLabel(context, today)}'),
            value: s.hebrewDates,
            onChanged: (v) => ctrl.update((x) => x.copyWith(hebrewDates: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.star_border),
            title: Text(l.jewishHolidays),
            subtitle: Text(
              '${l.jewishHolidaysHint}. ${israel ? l.holidaysScheduleIsrael : l.holidaysScheduleAbroad}',
            ),
            value: s.jewishHolidays,
            onChanged: (v) => ctrl.update((x) => x.copyWith(jewishHolidays: v)),
          ),
          ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: Text(l.shabbatTimes),
            subtitle: Text(city == null ? l.shabbatTimesOff : city.name(hebrew: hebrew)),
            onTap: () async {
              final picked = await showDialog<String>(
                context: context,
                builder: (d) => SimpleDialog(
                  title: Text(l.pickCity),
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.of(d).pop(''),
                      child: Text(l.shabbatTimesOff),
                    ),
                    for (final group in [true, false]) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                        child: Text(
                          group ? l.israelCities : l.otherCities,
                          style: Theme.of(d).textTheme.labelLarge,
                        ),
                      ),
                      for (final c in zmanimCities)
                        if (c.israel == group)
                          SimpleDialogOption(
                            onPressed: () => Navigator.of(d).pop(c.id),
                            child: Text(c.name(hebrew: hebrew)),
                          ),
                    ],
                  ],
                ),
              );
              if (picked != null) {
                await ctrl.update((x) => x.copyWith(shabbatCity: picked.isEmpty ? null : picked));
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
            child: Text(l.shabbatTimesHint, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (city != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
              child: Text(
                l.jewishTimesAt(city.name(hebrew: hebrew), city.candleMinutes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

