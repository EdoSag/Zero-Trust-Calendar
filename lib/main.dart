import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'data/shared_calendars.dart';
import 'app/app_gate.dart';
import 'app/calendar_config.dart';
import 'l10n/l10n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  // The language picked in Settings, so the first frame is already in it.
  await ZtLanguageController.preload();
  runApp(
    ProviderScope(
      overrides: [
        ztAppConfigProvider.overrideWithValue(calendarAppConfig),
        // Only admins rename or recolour a shared calendar for everyone.
        ztSpacePolicyProvider.overrideWithValue(calendarSpacePolicy),
      ],
      child: const ZeroTrustCalendarApp(),
    ),
  );
}

class ZeroTrustCalendarApp extends ConsumerWidget {
  const ZeroTrustCalendarApp({super.key, this.home = const AppGate()});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ZtThemeBuilder(
      builder: (context, theme, darkTheme, mode) => MaterialApp(
        // On-device task switcher label; the store name is Zero-Trust Calendar.
        title: 'ZT Calendar',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: mode,
        // English (default) or Hebrew, from Settings → Appearance → Language.
        locale: ref.watch(ztLanguageProvider),
        supportedLocales: ZtLanguages.supported,
        localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
        home: home,
        // Any touch on any screen counts as activity for auto-lock.
        builder: (BuildContext context, Widget? child) => Listener(
          onPointerDown: (_) => ref.read(vaultControllerProvider.notifier).touch(),
          child: child,
        ),
      ),
    );
  }
}
