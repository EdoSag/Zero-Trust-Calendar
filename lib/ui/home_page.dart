import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/calendar_settings.dart';
import '../data/calendar_store.dart';
import '../model/calendar_event.dart';
import '../util/format.dart';
import 'calendars_page.dart';
import 'month_view.dart';
import 'navigation.dart';
import 'schedule_view.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'timeline_view.dart';

const _viewLabels = {
  CalendarView.schedule: ('Schedule', Icons.view_agenda_outlined),
  CalendarView.day: ('Day', Icons.view_day_outlined),
  CalendarView.threeDay: ('3 days', Icons.view_column_outlined),
  CalendarView.week: ('Week', Icons.view_week_outlined),
  CalendarView.month: ('Month', Icons.calendar_view_month_outlined),
};

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _setView(WidgetRef ref, CalendarView view) =>
      ref.read(calendarSettingsProvider.notifier).update((s) => s.copyWith(view: view));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(calendarSettingsProvider);
    final focused = ref.watch(focusedDayProvider);
    final view = settings.view;

    void openDay(DateTime day) {
      ref.read(focusedDayProvider.notifier).set(day);
      _setView(ref, CalendarView.day);
    }

    final body = switch (view) {
      CalendarView.schedule => const ScheduleView(key: ValueKey('schedule')),
      CalendarView.day => TimelineView(key: const ValueKey('day'), days: 1, onOpenDay: openDay),
      CalendarView.threeDay => TimelineView(key: const ValueKey('3day'), days: 3, onOpenDay: openDay),
      CalendarView.week => TimelineView(key: const ValueKey('week'), days: 7, onOpenDay: openDay),
      CalendarView.month => MonthView(key: const ValueKey('month'), onOpenDay: openDay),
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: focused,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (d != null) ref.read(focusedDayProvider.notifier).set(d);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    focused.year == DateTime.now().year
                        ? DateFormat.MMMM().format(focused)
                        : formatMonthYear(focused),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
          IconButton(
            tooltip: 'Today',
            onPressed: () => ref.read(focusedDayProvider.notifier).today(),
            icon: _TodayIcon(day: DateTime.now().day),
          ),
          PopupMenuButton<CalendarView>(
            tooltip: 'Change view',
            icon: Icon(_viewLabels[view]!.$2),
            onSelected: (v) => _setView(ref, v),
            itemBuilder: (_) => [
              for (final v in CalendarView.values)
                CheckedPopupMenuItem(
                  value: v,
                  checked: v == view,
                  child: Text(_viewLabels[v]!.$1),
                ),
            ],
          ),
        ],
      ),
      drawer: _CalendarDrawer(onView: (v) => _setView(ref, v)),
      body: body,
      floatingActionButton: FloatingActionButton(
        tooltip: 'New event',
        onPressed: () => createEvent(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TodayIcon extends StatelessWidget {
  const _TodayIcon({required this.day});
  final int day;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      const Icon(Icons.calendar_today_outlined),
      Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text('$day', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
      ),
    ],
  );
}

class _CalendarDrawer extends ConsumerWidget {
  const _CalendarDrawer({required this.onView});
  final void Function(CalendarView) onView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(calendarSettingsProvider);
    final calendars = ref.watch(calendarsProvider).value ?? const [ZtCalendarInfo.personal];
    final theme = Theme.of(context);
    void push(Widget page) {
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Text('ZT Calendar', style: theme.textTheme.titleLarge),
        ),
        for (final v in CalendarView.values)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 28),
            leading: Icon(_viewLabels[v]!.$2),
            title: Text(_viewLabels[v]!.$1),
            selected: v == settings.view,
            onTap: () {
              Navigator.of(context).pop();
              onView(v);
            },
          ),
        const Divider(indent: 28, endIndent: 28),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 16, 4),
          child: Text('Calendars', style: theme.textTheme.titleSmall),
        ),
        for (final c in calendars)
          CheckboxListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: Color(c.color),
            side: BorderSide(color: Color(c.color), width: 2),
            value: !c.hidden,
            title: Text(c.name),
            onChanged: (on) => ref
                .read(calendarRepositoryProvider)
                .saveCalendar(c.copyWith(hidden: on != true)),
          ),
        CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          controlAffinity: ListTileControlAffinity.leading,
          value: settings.showTasks,
          title: const Text('Tasks from ZT Tasks'),
          onChanged: (on) => ref
              .read(calendarSettingsProvider.notifier)
              .update((s) => s.copyWith(showTasks: on == true)),
        ),
        CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          controlAffinity: ListTileControlAffinity.leading,
          value: settings.showBirthdays,
          title: const Text('Birthdays from ZT Contacts'),
          onChanged: (on) => ref
              .read(calendarSettingsProvider.notifier)
              .update((s) => s.copyWith(showBirthdays: on == true)),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.edit_calendar_outlined),
          title: const Text('Manage calendars'),
          onTap: () => push(const CalendarsPage()),
        ),
        const Divider(indent: 28, endIndent: 28),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28),
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () => push(const CalendarSettingsPage()),
        ),
      ],
    );
  }
}
