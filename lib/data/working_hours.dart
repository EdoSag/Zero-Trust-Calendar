import '../planner/planner_model.dart';

/// Working hours (K-7). They are the Planner's work hours, kept in the
/// Planner's synced settings, so there is one set for the whole account:
/// the Planner plans work tasks in them, Find a time offers slots in them,
/// and a booking page can copy them.
///
/// Before the Planner is set up there are none saved: the default work week
/// starting on [weekStart], 9:00 to 17:00.
Map<int, List<MinuteRange>> workingHoursOf(PlannerSettings settings, int weekStart) =>
    settings.hours[workHoursId] ?? PlannerSettings.defaultHours(weekStart)[workHoursId]!;

/// [settings] with [hours] as the working hours. When no hours were saved
/// yet, the other default hours (personal) come along, as the Planner's
/// setup would have saved them.
PlannerSettings withWorkingHours(
  PlannerSettings settings,
  Map<int, List<MinuteRange>> hours,
  int weekStart,
) => settings.copyWith(
  hours: {
    ...(settings.hours.isEmpty ? PlannerSettings.defaultHours(weekStart) : settings.hours),
    workHoursId: hours,
  },
);
