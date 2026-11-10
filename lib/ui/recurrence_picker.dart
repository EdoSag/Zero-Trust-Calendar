import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../model/recurrence.dart';
import '../util/format.dart';

/// Asks how an event repeats. Returns `(rule,)`, with a null rule for "does
/// not repeat", or null when cancelled.
Future<(RecurrenceRule?,)?> pickRecurrence(
  BuildContext context, {
  required DateTime start,
  RecurrenceRule? current,
}) async {
  final nth = (start.day - 1) ~/ 7 + 1;
  final isLast = addDays(start, 7).month != start.month;
  final presets = <RecurrenceRule?>[
    null,
    const RecurrenceRule(frequency: Frequency.daily),
    RecurrenceRule(frequency: Frequency.weekly, byDay: [WeekdayNum(start.weekday)]),
    const RecurrenceRule(
      frequency: Frequency.weekly,
      byDay: [
        WeekdayNum(DateTime.monday),
        WeekdayNum(DateTime.tuesday),
        WeekdayNum(DateTime.wednesday),
        WeekdayNum(DateTime.thursday),
        WeekdayNum(DateTime.friday),
      ],
    ),
    const RecurrenceRule(frequency: Frequency.monthly),
    RecurrenceRule(
      frequency: Frequency.monthly,
      byDay: [WeekdayNum(start.weekday, nth > 4 ? -1 : nth)],
    ),
    if (isLast && nth <= 4)
      RecurrenceRule(frequency: Frequency.monthly, byDay: [WeekdayNum(start.weekday, -1)]),
    const RecurrenceRule(frequency: Frequency.yearly),
  ];
  final isPreset = current == null || presets.contains(current);
  final picked = await showDialog<Object>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: const Text('Repeat'),
      children: [
        for (final rule in presets)
          _option(dialog, describeRule(rule, start), rule, rule == current),
        if (!isPreset) _option(dialog, describeRule(current, start), current, true),
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialog).pop('custom'),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Custom…'),
          ),
        ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return null;
  if (picked == 'custom') {
    final custom = await Navigator.of(context).push<RecurrenceRule>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CustomRecurrencePage(
          start: start,
          initial: current ?? RecurrenceRule(
            frequency: Frequency.weekly,
            byDay: [WeekdayNum(start.weekday)],
          ),
        ),
      ),
    );
    return custom == null ? null : (custom,);
  }
  return ((picked as _Picked).rule,);
}

class _Picked {
  const _Picked(this.rule);
  final RecurrenceRule? rule;
}

Widget _option(BuildContext dialog, String label, RecurrenceRule? rule, bool selected) =>
    SimpleDialogOption(
      onPressed: () => Navigator.of(dialog).pop(_Picked(rule)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            if (selected) const Icon(Icons.check, size: 20),
          ],
        ),
      ),
    );

/// Every N days/weeks/months/years, on chosen weekdays, ending never, on a
/// date or after a number of times.
class CustomRecurrencePage extends StatefulWidget {
  const CustomRecurrencePage({super.key, required this.start, required this.initial});

  final DateTime start;
  final RecurrenceRule initial;

  @override
  State<CustomRecurrencePage> createState() => _CustomRecurrencePageState();
}

enum _End { never, onDate, after }

class _CustomRecurrencePageState extends State<CustomRecurrencePage> {
  late Frequency _freq = widget.initial.frequency;
  late int _interval = widget.initial.interval;
  late Set<int> _weekdays = {
    for (final d in widget.initial.byDay) d.weekday,
    if (widget.initial.byDay.isEmpty) widget.start.weekday,
  };
  late bool _monthlyByWeekday = widget.initial.byDay.any((d) => d.n != null);
  late _End _end = widget.initial.count != null
      ? _End.after
      : widget.initial.until != null
      ? _End.onDate
      : _End.never;
  late DateTime _until = widget.initial.until ?? addDays(widget.start, 90);
  late int _count = widget.initial.count ?? 10;
  late final _intervalText = TextEditingController(text: '$_interval');
  late final _countText = TextEditingController(text: '$_count');

  @override
  void dispose() {
    _intervalText.dispose();
    _countText.dispose();
    super.dispose();
  }

  RecurrenceRule _build() {
    final nth = (widget.start.day - 1) ~/ 7 + 1;
    return RecurrenceRule(
      frequency: _freq,
      interval: _interval,
      count: _end == _End.after ? _count : null,
      until: _end == _End.onDate
          ? DateTime(_until.year, _until.month, _until.day, 23, 59, 59)
          : null,
      byDay: switch (_freq) {
        Frequency.weekly => [for (final d in (_weekdays.toList()..sort())) WeekdayNum(d)],
        Frequency.monthly when _monthlyByWeekday => [
          WeekdayNum(widget.start.weekday, nth > 4 ? -1 : nth),
        ],
        _ => const [],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Monday-first chips; the order a user expects doesn't change meaning.
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Custom repeat'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_build()),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Repeats every', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _intervalText,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  onChanged: (v) => setState(
                    () => _interval = (int.tryParse(v) ?? 1).clamp(1, 999),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<Frequency>(
                value: _freq,
                onChanged: (f) => setState(() => _freq = f ?? _freq),
                items: [
                  for (final f in Frequency.values)
                    DropdownMenuItem(
                      value: f,
                      child: Text(switch (f) {
                        Frequency.daily => _interval == 1 ? 'day' : 'days',
                        Frequency.weekly => _interval == 1 ? 'week' : 'weeks',
                        Frequency.monthly => _interval == 1 ? 'month' : 'months',
                        Frequency.yearly => _interval == 1 ? 'year' : 'years',
                      }),
                    ),
                ],
              ),
            ],
          ),
          if (_freq == Frequency.weekly) ...[
            const SizedBox(height: 20),
            Text('On', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(letters[d - 1]),
                    tooltip: DateFormat.EEEE().format(DateTime(2024, 1, d)),
                    selected: _weekdays.contains(d),
                    showCheckmark: false,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _weekdays = {..._weekdays, d};
                      } else if (_weekdays.length > 1) {
                        _weekdays = {..._weekdays}..remove(d);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (_freq == Frequency.monthly) ...[
            const SizedBox(height: 20),
            RadioGroup<bool>(
              groupValue: _monthlyByWeekday,
              onChanged: (v) => setState(() => _monthlyByWeekday = v ?? false),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text('On day ${widget.start.day}'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text(
                      describeRule(
                        RecurrenceRule(
                          frequency: Frequency.monthly,
                          byDay: [
                            WeekdayNum(
                              widget.start.weekday,
                              ((widget.start.day - 1) ~/ 7 + 1) > 4
                                  ? -1
                                  : (widget.start.day - 1) ~/ 7 + 1,
                            ),
                          ],
                        ),
                        widget.start,
                      ).replaceFirst('Every month ', '').replaceFirst('on t', 'On t'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('Ends', style: theme.textTheme.titleSmall),
          RadioGroup<_End>(
            groupValue: _end,
            onChanged: (v) => setState(() => _end = v ?? _End.never),
            child: Column(
              children: [
                const RadioListTile<_End>(value: _End.never, title: Text('Never')),
                RadioListTile<_End>(
                  value: _End.onDate,
                  title: Row(
                    children: [
                      const Text('On '),
                      TextButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _until,
                            firstDate: widget.start,
                            lastDate: DateTime(widget.start.year + 50),
                          );
                          if (d != null) {
                            setState(() {
                              _until = d;
                              _end = _End.onDate;
                            });
                          }
                        },
                        child: Text(DateFormat.yMMMd().format(_until)),
                      ),
                    ],
                  ),
                ),
                RadioListTile<_End>(
                  value: _End.after,
                  title: Row(
                    children: [
                      const Text('After '),
                      SizedBox(
                        width: 56,
                        child: TextField(
                          controller: _countText,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onTap: () => setState(() => _end = _End.after),
                          onChanged: (v) => setState(
                            () => _count = (int.tryParse(v) ?? 1).clamp(1, 9999),
                          ),
                        ),
                      ),
                      Text(' ${_count == 1 ? 'time' : 'times'}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            describeRule(_build(), widget.start),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
