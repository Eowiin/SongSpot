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
import 'providers/coin_shop_provider.dart';
import 'providers/game_provider.dart';
import 'providers/pack_bundle_provider.dart';
import 'providers/pack_provider.dart';
import 'providers/room_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/game/game_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/admob_service.dart';
import 'services/consent_service.dart';
import 'services/push_notification_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.environment = const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'development',
      );
      options.tracesSampleRate = 0.1;
      // Never send errors in debug mode
      options.beforeSend = (event, hint) => kDebugMode ? null : event;
    },
    appRunner: () async {
      await dotenv.load(fileName: '.env');
      // runApp first so the Flutter Activity is fully rendered before the UMP
      // consent form Activity is launched. On older Android, showing a new Activity
      // before runApp() causes it to appear behind the main Activity (grey screen).
      runApp(const MyApp());
      unawaited(_initializeServices());
    },
  );
}

Future<void> _initializeServices() async {
  await _run(ConsentService().gatherConsent);
  await _run(AdMobService().initialize);
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
        // Clear any active text selection/focus before backgrounding so Android
        // doesn't resume into a half-focused field with no visible keyboard.
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
        ChangeNotifierProvider(create: (_) => RoomProvider()),
        ChangeNotifierProvider(create: (_) => GameProvider()),
        ChangeNotifierProvider(create: (_) => PackProvider()),
        ChangeNotifierProvider(create: (_) => PackBundleProvider()),
        ChangeNotifierProxyProvider<AuthProvider, CoinShopProvider>(
          create: (_) => CoinShopProvider(),
          update: (_, auth, shop) => shop!..setAuthProvider(auth),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            // Localization
            locale: settings.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            // Theme (high contrast / color blindness override)
            theme: settings.currentTheme,
            // Apply text scale and animation speed via builder
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
    // Run auth check and consent in parallel; consent attaches to the
    // in-flight singleton future so no second form is ever shown.
    // Waiting here ensures we don't navigate while the consent form is visible,
    // which would cause it to flicker/refresh on Android.
    await Future.wait([
      authProvider.checkAuthStatus(),
      ConsentService().gatherConsent(),
    ]);

    if (mounted) {
      // Set up push notification tap handler
      PushNotificationService().setOnNotificationTap(_handleNotificationTap);

      if (authProvider.isAuthenticated) {
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
    final type = data['type'] as String?;
    final roomId = data['room_id'] as String?;
    if (roomId == null) return;

    if (type == 'daily_song_available') {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => GameScreen(roomId: roomId)),
      );
    }
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
              Icon(Icons.music_note, size: 100, color: AppTheme.primaryColor),
              SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).appTitle,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
