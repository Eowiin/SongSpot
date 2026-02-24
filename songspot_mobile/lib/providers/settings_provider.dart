import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../services/push_notification_service.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyTextScale = 'settings_text_scale';
  static const _keyReduceAnimations = 'settings_reduce_animations';
  static const _keyHighContrast = 'settings_high_contrast';
  static const _keyColorBlindness = 'settings_color_blindness';
  static const _keyLocale = 'settings_locale';
  static const _keyDailySongNotifs = 'settings_daily_song_notifs';
  static const _keyMessagesNotifs = 'settings_messages_notifs';
  static const _keyEnhancedSemantics = 'settings_enhanced_semantics';

  double _textScaleFactor = 1.0;
  bool _reduceAnimations = false;
  bool _highContrast = false;
  ColorBlindnessMode _colorBlindnessMode = ColorBlindnessMode.none;
  Locale _locale = const Locale('en');
  bool _dailySongNotifications = true;
  bool _messagesNotifications = true;
  bool _enhancedSemantics = false;

  double get textScaleFactor => _textScaleFactor;
  bool get reduceAnimations => _reduceAnimations;
  bool get highContrast => _highContrast;
  ColorBlindnessMode get colorBlindnessMode => _colorBlindnessMode;
  Locale get locale => _locale;
  bool get dailySongNotifications => _dailySongNotifications;
  bool get messagesNotifications => _messagesNotifications;
  bool get enhancedSemantics => _enhancedSemantics;

  ThemeData get currentTheme {
    if (_highContrast) return AppTheme.highContrastTheme;
    return AppTheme.getThemeForColorBlindness(_colorBlindnessMode);
  }

  SettingsProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _textScaleFactor = prefs.getDouble(_keyTextScale) ?? 1.0;
    _reduceAnimations = prefs.getBool(_keyReduceAnimations) ?? false;
    _highContrast = prefs.getBool(_keyHighContrast) ?? false;
    _colorBlindnessMode = ColorBlindnessMode.values[prefs.getInt(_keyColorBlindness) ?? 0];
    _locale = Locale(prefs.getString(_keyLocale) ?? 'en');
    _dailySongNotifications = prefs.getBool(_keyDailySongNotifs) ?? true;
    _messagesNotifications = prefs.getBool(_keyMessagesNotifs) ?? true;
    _enhancedSemantics = prefs.getBool(_keyEnhancedSemantics) ?? false;
    notifyListeners();
  }

  Future<void> setTextScaleFactor(double value) async {
    _textScaleFactor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyTextScale, value);
  }

  Future<void> setReduceAnimations(bool value) async {
    _reduceAnimations = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReduceAnimations, value);
  }

  Future<void> setHighContrast(bool value) async {
    _highContrast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHighContrast, value);
  }

  Future<void> setColorBlindnessMode(ColorBlindnessMode mode) async {
    _colorBlindnessMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyColorBlindness, mode.index);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLocale, locale.languageCode);
  }

  Future<void> setDailySongNotifications(bool value) async {
    _dailySongNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDailySongNotifs, value);
    await PushNotificationService().updateNotificationPrefs(
      dailySong: _dailySongNotifications,
      messages: _messagesNotifications,
    );
  }

  Future<void> setMessagesNotifications(bool value) async {
    _messagesNotifications = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMessagesNotifs, value);
    await PushNotificationService().updateNotificationPrefs(
      dailySong: _dailySongNotifications,
      messages: _messagesNotifications,
    );
  }

  Future<void> setEnhancedSemantics(bool value) async {
    _enhancedSemantics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnhancedSemantics, value);
  }
}
