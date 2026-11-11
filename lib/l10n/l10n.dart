import 'package:flutter/widgets.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'generated/app_l10n.dart';

export 'generated/app_l10n.dart';

/// ZT Calendar's own strings, in English and Hebrew (`app_en.arb`,
/// `app_he.arb`). The language is the one picked under Settings →
/// Appearance → Language (`ztLanguageProvider` in the core).
extension AppL10nContext on BuildContext {
  AppL10n get l10n => AppL10n.of(this);
}

/// The strings for the app's current language, for code without a
/// [BuildContext] (notifications, the home screen widget, exports).
AppL10n get currentL10n {
  final code = ZtL10n.current.localeName.split('_').first;
  return lookupAppL10n(
    AppL10n.supportedLocales.any((l) => l.languageCode == code)
        ? Locale(code)
        : const Locale('en'),
  );
}

/// The strings for the language picked in Settings ([ztLanguageProvider]'s
/// value; null follows the phone). Unlike [currentL10n] this is right the
/// moment the setting changes, before the app has rebuilt in it.
AppL10n appL10nFor(Locale? picked) {
  final code = (picked ?? WidgetsBinding.instance.platformDispatcher.locale).languageCode;
  return lookupAppL10n(
    AppL10n.supportedLocales.any((l) => l.languageCode == code)
        ? Locale(code)
        : const Locale('en'),
  );
}

/// Keeps [text] left-to-right inside Hebrew (numbers with units, emails).
String ltr(String text) => text.isEmpty ? text : '\u2066$text\u2069';


/// A public holiday calendar's region, as the subscribe list shows it.
String holidayRegionName(String name) {
  final l = currentL10n;
  return switch (name) {
    'Israel (Jewish holidays)' => l.regionIsraelJewishHolidays,
    'Israel (Jewish holidays, Hebrew)' => l.regionIsraelJewishHolidaysHebrew,
    'United States' => l.regionUnitedStates,
    'United Kingdom' => l.regionUnitedKingdom,
    'Canada' => l.regionCanada,
    'Australia' => l.regionAustralia,
    'Ireland' => l.regionIreland,
    'Germany' => l.regionGermany,
    'France' => l.regionFrance,
    'Italy' => l.regionItaly,
    'Spain' => l.regionSpain,
    'Netherlands' => l.regionNetherlands,
    'Portugal' => l.regionPortugal,
    'Poland' => l.regionPoland,
    'Sweden' => l.regionSweden,
    'Russia' => l.regionRussia,
    'India' => l.regionIndia,
    'Japan' => l.regionJapan,
    'China' => l.regionChina,
    'Brazil' => l.regionBrazil,
    'Mexico' => l.regionMexico,
    'South Africa' => l.regionSouthAfrica,
    'Christian holidays' => l.regionChristianHolidays,
    'Islamic holidays' => l.regionIslamicHolidays,
    _ => name,
  };
}
