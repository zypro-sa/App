import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_settings.dart';
import 'core/config.dart';
import 'core/i18n.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  try {
    appPrefs = await SharedPreferences.getInstance();
  } catch (_) {
    appPrefs = null;
  }
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );
  runApp(const ProviderScope(child: PersonalAssistantApp()));
}

class PersonalAssistantApp extends ConsumerStatefulWidget {
  const PersonalAssistantApp({super.key});

  @override
  ConsumerState<PersonalAssistantApp> createState() => _PersonalAssistantAppState();
}

class _PersonalAssistantAppState extends ConsumerState<PersonalAssistantApp> with WidgetsBindingObserver {
  String? _applied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // مظهر الجوال تغيّر (مثل الوضع الليلي التلقائي)
  @override
  void didChangePlatformBrightness() {
    if (ref.read(appSettingsProvider).themeMode == ThemeMode.system) setState(() {});
  }

  /// إعادة بناء كل الشاشات المفتوحة لتأخذ الألوان والنصوص الجديدة.
  void _rebuildAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    if (mounted) (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    // لغة العضو المحفوظة في ملفه (لأول دخول على الجهاز)
    ref.listen(profileProvider, (_, next) {
      ref.read(appSettingsProvider.notifier).adoptProfileLocale(next.valueOrNull?.locale);
    });

    final platformDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final dark = switch (settings.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformDark,
    };
    AppColors.dark = dark;
    L.code = settings.locale;
    AppIcons.ltr = L.isEn;

    final key = '${dark ? 'd' : 'l'}-${settings.locale}';
    if (_applied != null && _applied != key) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    _applied = key;

    return MaterialApp.router(
      title: 'Zypro',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.light, // الألوان تُحسب في buildTheme حسب الاختيار
      routerConfig: appRouter,
      locale: Locale(settings.locale),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
