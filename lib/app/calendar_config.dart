import 'package:flutter/material.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Calendar in the suite. Not in the core's `ZtSuite` list yet, so the other
/// apps don't link to it before it's released.
const ZtSuiteApp calendarSuiteApp = ZtSuiteApp(
  appId: 'calendar',
  name: 'Calendar',
  tagline: 'Events, reminders and schedules',
  icon: Icons.calendar_month_outlined,
  accent: Color(0xFFF97316), // orange
  androidPackage: 'dev.sagron.zerotrustcalendar',
);

const ZtAppConfig calendarAppConfig = ZtAppConfig(
  appId: 'calendar',
  displayName: 'Zero-Trust Calendar',
  accent: Color(0xFFF97316),
);
