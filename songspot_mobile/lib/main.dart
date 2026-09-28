import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_theme.dart';
import 'config/sentry_filters.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/game_session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/stats_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/analytics_service.dart';
import 'services/audio_service.dart';
import 'services/boot_splash.dart';
import 'services/consent_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/push_notification_service.dart';

/// Whether [state] means the app has really left the foreground.
///
/// `inactive` does not mean that everywhere. On the web it is a plain window
/// blur — an alt-tab, or a click on another window, with the tab still on
/// screen. On Android it means the activity lost window focus while still
/// resumed, which any system window causes: the notification shade, a heads-up
/// notification, and — the reason this matters — the autofill sheet that opens
/// over the login form the instant a hinted field is tapped. Treating that as a
/// departure dropped the focus the user had just given the field, so the
/// keyboard closed on every attempt and signing in became impossible.
///
/// Both still report `hidden` and then `paused` when they go away for real, so
/// nothing is lost by sitting `inactive` out. iOS keeps acting on it: there it
/// is the app switcher, control centre or an incoming call, and the snippet
/// should stop for those.
bool leavesForeground(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) return false;
  if (state != AppLifecycleState.inactive) return true;
  return !kIsWeb && defaultTargetPlatform != TargetPlatform.android;
}

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
        // The native iOS SDK reports every failed URLSession request, which
        // in practice means Firebase's own 5xx retries rather than anything
        // in this app. Dart-side capturing stays on, so failures of our own
        // API calls are still reported.
        options.captureNativeFailedRequests = false;
        // App-hang detection watches the iOS main thread, but Dart runs on
        // Flutter's own UI thread, so a hang in our code never shows up there.
        // What it did report was the system keyboard cold-loading on first
        // focus — native events that beforeSend cannot filter.
        options.enableAppHangTracking = false;
        options.beforeSend = (event, hint) {
          if (kDebugMode) return null;
          if (isDroppedSentryEvent(event)) return null;
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
  // Firebase first and on its own: analytics and push both need it, and
  // neither should be able to take the other down by failing.
  await _run(FirebaseBootstrap.ensureInitialized);
  await _run(AnalyticsService().initialize);
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
    // Hand the screen over from the HTML boot splash to the Flutter one.
    WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!leavesForeground(state)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // Stop any snippet when the app leaves the foreground: on Android the
    // audio would otherwise keep playing off-screen, and on iOS it would
    // resume mid-clip on return instead of resetting. Ending it here also
    // releases the play button so the player taps to replay from the start.
    // On the web it also keeps the snippet honest — a hidden tab's timers are
    // throttled to about one tick a second, so the timer that cuts the clip
    // would overrun and hand out more of the song than the difficulty allows.
    AudioService().haltForInterruption();
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
    // Picks up where the HTML boot splash leaves off, so the handover on web
    // is not a jump between two different identities.
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              ),
            ),
            const SizedBox(height: 22),
            Text.rich(
              TextSpan(
                text: AppLocalizations.of(context).appTitle.toUpperCase(),
                children: [
                  TextSpan(
                    text: '.',
                    style: AppTheme.display(24, color: AppTheme.accentColor),
                  ),
                ],
              ),
              style: AppTheme.display(24).copyWith(letterSpacing: 3),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: AppTheme.line,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
