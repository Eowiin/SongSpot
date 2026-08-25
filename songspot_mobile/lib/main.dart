import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/game_session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/stats_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/consent_service.dart';
import 'services/push_notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.environment = const String.fromEnvironment(
          'SENTRY_ENVIRONMENT',
          defaultValue: 'development',
        );
        options.tracesSampleRate = 0.1;
        options.beforeSend = (event, hint) {
          if (kDebugMode) return null;
          // google_fonts fetches TTFs over the network on first use; on a
          // dropped/offline connection it throws unhandled, which is a
          // device connectivity issue rather than an app bug. Drop it to
          // avoid flooding Sentry with non-actionable noise.
          final message = event.throwable?.toString() ?? '';
          if (message.contains('Failed to load font with url')) return null;
          return event;
        };
      },
      appRunner: () async {
        await dotenv.load(fileName: '.env');
        runApp(const MyApp());
        unawaited(_initializeServices());
      },
    );
  } else {
    await dotenv.load(fileName: '.env');
    runApp(const MyApp());
    unawaited(_initializeServices());
  }
}

Future<void> _initializeServices() async {
  await _run(ConsentService().gatherConsent);
  await _run(PushNotificationService().initializeCore);
}

Future<void> _run(Future<void> Function() task) async {
  try {
    await task();
  } catch (_) {}
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        FocusManager.instance.primaryFocus?.unfocus();
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GameSessionProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            locale: settings.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: settings.currentTheme,
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(settings.textScaleFactor),
                  disableAnimations: settings.reduceAnimations,
                ),
                child: child!,
              );
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final authProvider = context.read<AuthProvider>();
    await Future.wait([
      authProvider.checkAuthStatus(),
      ConsentService().gatherConsent(),
    ]);

    if (mounted) {
      PushNotificationService().setOnNotificationTap(_handleNotificationTap);

      if (authProvider.isAuthenticated || authProvider.isGuest) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    // Push notification handling — reserved for future use
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_note, size: 100, color: AppTheme.primaryColor),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).appTitle,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
