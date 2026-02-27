import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// The name of the application
  ///
  /// In en, this message translates to:
  /// **'SongSpot'**
  String get appTitle;

  /// Generic loading text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirm action
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Save action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Submit action
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// Generic error label
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Generic success label
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// Logout action
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// Title of the logout confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutConfirmTitle;

  /// Message in the logout confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to logout?'**
  String get logoutConfirmMessage;

  /// Create new room button
  ///
  /// In en, this message translates to:
  /// **'Create New Room'**
  String get createRoom;

  /// Join a room section title
  ///
  /// In en, this message translates to:
  /// **'Join a Room'**
  String get joinRoom;

  /// My rooms section title
  ///
  /// In en, this message translates to:
  /// **'My Rooms'**
  String get myRooms;

  /// Empty state for rooms list
  ///
  /// In en, this message translates to:
  /// **'No rooms yet'**
  String get noRoomsYet;

  /// Hint when no rooms exist
  ///
  /// In en, this message translates to:
  /// **'Create or join a room to start playing!'**
  String get noRoomsHint;

  /// Placeholder for room code input
  ///
  /// In en, this message translates to:
  /// **'Enter room code'**
  String get enterRoomCode;

  /// Member count label
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String members(num count);

  /// Login screen title
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginTitle;

  /// Login screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue playing'**
  String get loginSubtitle;

  /// Email input label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// Password input label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Login button
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// Prompt to register
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccountPrompt;

  /// Link to register
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerLink;

  /// Register screen title
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// Register screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Join SongSpot and start guessing'**
  String get registerSubtitle;

  /// Username input label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// Confirm password input label
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// Register button
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// Prompt to login
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// Link to login
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginLink;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Account section header in settings
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsSectionAccount;

  /// Notifications section header in settings
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsSectionNotifications;

  /// Accessibility section header in settings
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsSectionAccessibility;

  /// Language section header in settings
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// My Data section header in settings
  ///
  /// In en, this message translates to:
  /// **'My Data'**
  String get settingsSectionMyData;

  /// About section header in settings
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Change email tile
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get settingsChangeEmail;

  /// Change password tile
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// Daily song notifications toggle
  ///
  /// In en, this message translates to:
  /// **'Daily song notifications'**
  String get settingsDailySongNotifications;

  /// Message notifications toggle
  ///
  /// In en, this message translates to:
  /// **'Message notifications'**
  String get settingsMessageNotifications;

  /// Accessibility tile
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsAccessibility;

  /// Language tile
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Export data tile
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get settingsExportData;

  /// Export data tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Download a copy of all your personal data'**
  String get settingsExportDataSubtitle;

  /// Delete account tile
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get settingsDeleteAccount;

  /// Delete account tile subtitle
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all data'**
  String get settingsDeleteAccountSubtitle;

  /// App version tile
  ///
  /// In en, this message translates to:
  /// **'App version'**
  String get settingsAppVersion;

  /// Privacy policy tile
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// Terms of service tile
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTermsOfService;

  /// Accessibility screen title
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibilityTitle;

  /// Text size section
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get accessibilityTextSize;

  /// Text size preview label
  ///
  /// In en, this message translates to:
  /// **'Preview text at this size'**
  String get accessibilityTextSizePreview;

  /// Small text size label
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get accessibilityTextSizeSmall;

  /// Large text size label
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get accessibilityTextSizeLarge;

  /// Reduce animations toggle
  ///
  /// In en, this message translates to:
  /// **'Reduce animations'**
  String get accessibilityReduceAnimations;

  /// Reduce animations subtitle
  ///
  /// In en, this message translates to:
  /// **'Minimize motion throughout the app'**
  String get accessibilityReduceAnimationsSubtitle;

  /// High contrast toggle
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get accessibilityHighContrast;

  /// High contrast subtitle
  ///
  /// In en, this message translates to:
  /// **'Increase color contrast for readability'**
  String get accessibilityHighContrastSubtitle;

  /// Color blindness section
  ///
  /// In en, this message translates to:
  /// **'Color blindness mode'**
  String get accessibilityColorBlindness;

  /// No color blindness mode
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get accessibilityColorBlindnessNone;

  /// Deuteranopia mode
  ///
  /// In en, this message translates to:
  /// **'Deuteranopia (red-green)'**
  String get accessibilityColorBlindnessDeuteranopia;

  /// Protanopia mode
  ///
  /// In en, this message translates to:
  /// **'Protanopia (red)'**
  String get accessibilityColorBlindnessProtanopia;

  /// Tritanopia mode
  ///
  /// In en, this message translates to:
  /// **'Tritanopia (blue-yellow)'**
  String get accessibilityColorBlindnessTritanopia;

  /// Enhanced screen reader toggle
  ///
  /// In en, this message translates to:
  /// **'Enhanced screen reader'**
  String get accessibilityEnhancedScreenReader;

  /// Enhanced screen reader subtitle
  ///
  /// In en, this message translates to:
  /// **'Add more descriptive labels for VoiceOver / TalkBack'**
  String get accessibilityEnhancedScreenReaderSubtitle;

  /// Language screen title
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// English language option
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// French language option
  ///
  /// In en, this message translates to:
  /// **'Français'**
  String get languageFrench;

  /// Change email screen title
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmailTitle;

  /// Current password label
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get changeEmailCurrentPassword;

  /// New email label
  ///
  /// In en, this message translates to:
  /// **'New email address'**
  String get changeEmailNewEmail;

  /// Update email button
  ///
  /// In en, this message translates to:
  /// **'Update email'**
  String get changeEmailButton;

  /// Email update success message
  ///
  /// In en, this message translates to:
  /// **'Email updated successfully'**
  String get changeEmailSuccess;

  /// Change password screen title
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePasswordTitle;

  /// Current password label
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get changePasswordCurrent;

  /// New password label
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get changePasswordNew;

  /// Confirm new password label
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get changePasswordConfirm;

  /// Update password button
  ///
  /// In en, this message translates to:
  /// **'Update password'**
  String get changePasswordButton;

  /// Password update success message
  ///
  /// In en, this message translates to:
  /// **'Password updated. Please log in again.'**
  String get changePasswordSuccess;

  /// My Data screen title
  ///
  /// In en, this message translates to:
  /// **'My Data'**
  String get myDataTitle;

  /// Export data section title
  ///
  /// In en, this message translates to:
  /// **'Export your data'**
  String get myDataExportTitle;

  /// Export data description
  ///
  /// In en, this message translates to:
  /// **'Download a copy of all your personal data including your profile, game history, messages, and coin transactions.'**
  String get myDataExportDescription;

  /// Export data button
  ///
  /// In en, this message translates to:
  /// **'Export my data'**
  String get myDataExportButton;

  /// Delete account section title
  ///
  /// In en, this message translates to:
  /// **'Delete your account'**
  String get myDataDeleteTitle;

  /// Delete account description
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all associated data. This action cannot be undone.'**
  String get myDataDeleteDescription;

  /// Delete account button
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get myDataDeleteButton;

  /// Delete confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get myDataDeleteConfirmTitle;

  /// Delete confirmation dialog message
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete your account and all your data. Enter your password to confirm.'**
  String get myDataDeleteConfirmMessage;

  /// Confirm delete button
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get myDataDeleteConfirmButton;

  /// Invalid password error
  ///
  /// In en, this message translates to:
  /// **'Invalid password'**
  String get invalidPassword;

  /// Invalid email error
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmail;

  /// Passwords mismatch error
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// Required field error
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// Undo button/action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoAction;

  /// Fallback username label
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userFallback;

  /// Tooltip for daily streak chip
  ///
  /// In en, this message translates to:
  /// **'Daily streak'**
  String get dailyStreakTooltip;

  /// Tooltip for coins chip
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get coinsTooltip;

  /// Validation when room code is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter a room code'**
  String get pleaseEnterRoomCode;

  /// Warning shown when another room deletion is pending
  ///
  /// In en, this message translates to:
  /// **'Finish or undo the current room deletion first.'**
  String get finishOrUndoCurrentRoomDeletion;

  /// Swipe delete snackbar content when host transfer happens
  ///
  /// In en, this message translates to:
  /// **'Left room. Host transferred.'**
  String get leftRoomHostTransferred;

  /// Swipe delete snackbar content
  ///
  /// In en, this message translates to:
  /// **'Room removed.'**
  String get roomRemoved;

  /// Shown after tapping undo for room deletion
  ///
  /// In en, this message translates to:
  /// **'Deletion cancelled.'**
  String get roomDeletionCancelled;

  /// Delete label in swipe background
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteLabel;

  /// Fallback delete error message
  ///
  /// In en, this message translates to:
  /// **'Could not delete room.'**
  String get couldNotDeleteRoom;

  /// Coin shop screen title
  ///
  /// In en, this message translates to:
  /// **'Coin Shop'**
  String get coinShopTitle;

  /// Shown when rewarded ad cannot be displayed
  ///
  /// In en, this message translates to:
  /// **'Ad not ready yet. Please try again in a moment.'**
  String get adNotReadyTryAgain;

  /// Shown when IAP store is unavailable
  ///
  /// In en, this message translates to:
  /// **'Store not available on this device.'**
  String get storeNotAvailableOnDevice;

  /// Shown when store products are missing
  ///
  /// In en, this message translates to:
  /// **'Products not found in store. Make sure in-app products are created and set to Active in App Store Connect / Play Console.'**
  String get productsNotFoundStoreMessage;

  /// Section title in coin shop
  ///
  /// In en, this message translates to:
  /// **'Get more coins'**
  String get getMoreCoinsTitle;

  /// Coin shop helper text
  ///
  /// In en, this message translates to:
  /// **'Use coins to unlock song packs and hints.'**
  String get useCoinsToUnlockHint;

  /// Payment overlay title
  ///
  /// In en, this message translates to:
  /// **'Processing payment...'**
  String get processingPayment;

  /// Payment overlay subtitle
  ///
  /// In en, this message translates to:
  /// **'Please don\'t close the app'**
  String get pleaseDontCloseApp;

  /// Coin balance header label
  ///
  /// In en, this message translates to:
  /// **'Your balance'**
  String get yourBalance;

  /// Generic coins amount label
  ///
  /// In en, this message translates to:
  /// **'{count} coins'**
  String coinsAmount(num count);

  /// Rewarded card title in coin shop
  ///
  /// In en, this message translates to:
  /// **'Free Bonus Coins'**
  String get freeBonusCoinsTitle;

  /// Rewarded card helper text
  ///
  /// In en, this message translates to:
  /// **'Watch a rewarded ad to claim +{coins} coins.'**
  String watchRewardedAdClaimCoins(num coins);

  /// Reward status loading text
  ///
  /// In en, this message translates to:
  /// **'Checking daily limit...'**
  String get checkingDailyLimit;

  /// Reward status unavailable text
  ///
  /// In en, this message translates to:
  /// **'Daily limit unavailable right now.'**
  String get dailyLimitUnavailable;

  /// Remaining rewarded claims status
  ///
  /// In en, this message translates to:
  /// **'Remaining today: {remaining} / {cap}'**
  String remainingTodayStatus(num remaining, num cap);

  /// Reward button label when cap reached
  ///
  /// In en, this message translates to:
  /// **'Daily Limit Reached'**
  String get dailyLimitReached;

  /// Reward button label
  ///
  /// In en, this message translates to:
  /// **'Watch Ad'**
  String get watchAdLabel;

  /// Inline rewarded ad success message in coin shop
  ///
  /// In en, this message translates to:
  /// **'+{coins} coins added to your balance.'**
  String rewardCoinsAddedToBalance(num coins);

  /// IAP success snackbar in coin shop
  ///
  /// In en, this message translates to:
  /// **'+{coins} coins added!'**
  String coinsAddedSuccess(num coins);

  /// Backend room hosted limit error
  ///
  /// In en, this message translates to:
  /// **'Room limit reached. Delete or leave one room before creating another.'**
  String get backendRoomLimitReached;

  /// Backend daily room creation limit error
  ///
  /// In en, this message translates to:
  /// **'Daily room creation limit reached. Try again tomorrow.'**
  String get backendDailyRoomCreationLimitReached;

  /// Backend room join duplicate error
  ///
  /// In en, this message translates to:
  /// **'You are already in this room.'**
  String get backendAlreadyInRoom;

  /// Backend room membership error
  ///
  /// In en, this message translates to:
  /// **'You are not in this room.'**
  String get backendNotInRoom;

  /// Backend room rename permission error
  ///
  /// In en, this message translates to:
  /// **'Only the host can rename the room.'**
  String get backendOnlyHostCanRenameRoom;

  /// Backend room not found error
  ///
  /// In en, this message translates to:
  /// **'Room not found.'**
  String get backendRoomNotFound;

  /// Backend insufficient coins error
  ///
  /// In en, this message translates to:
  /// **'Insufficient coins.'**
  String get backendInsufficientCoins;

  /// Backend no retries remaining error
  ///
  /// In en, this message translates to:
  /// **'No retries remaining.'**
  String get backendNoRetriesRemaining;

  /// Backend retry requirement error
  ///
  /// In en, this message translates to:
  /// **'Retry is only available after the last snippet.'**
  String get backendRetryAfterLastSnippetOnly;

  /// Backend game already completed error
  ///
  /// In en, this message translates to:
  /// **'Game already completed.'**
  String get backendGameAlreadyCompleted;

  /// Backend missing active game session error
  ///
  /// In en, this message translates to:
  /// **'No active game session.'**
  String get backendNoActiveGameSession;

  /// Backend no daily song error
  ///
  /// In en, this message translates to:
  /// **'No song available for today.'**
  String get backendNoSongAvailableToday;

  /// Backend room pack ownership error
  ///
  /// In en, this message translates to:
  /// **'This pack is not owned by the room.'**
  String get backendPackNotOwnedByRoom;

  /// Backend empty pack error
  ///
  /// In en, this message translates to:
  /// **'This pack has no tracks.'**
  String get backendPackHasNoTracks;

  /// Backend missing active pack session error
  ///
  /// In en, this message translates to:
  /// **'No active pack session.'**
  String get backendNoActivePackSession;

  /// Backend completed pack session error
  ///
  /// In en, this message translates to:
  /// **'Pack already completed.'**
  String get backendPackAlreadyCompleted;

  /// Backend track not found error
  ///
  /// In en, this message translates to:
  /// **'Track not found.'**
  String get backendTrackNotFound;

  /// Backend duplicate stage guess error
  ///
  /// In en, this message translates to:
  /// **'You already guessed for this stage.'**
  String get backendAlreadyGuessedForStage;

  /// Backend missing room id error
  ///
  /// In en, this message translates to:
  /// **'Room is required.'**
  String get backendRoomIdRequired;

  /// Backend invalid password error
  ///
  /// In en, this message translates to:
  /// **'Invalid password.'**
  String get backendInvalidPassword;

  /// Backend invalid current password error
  ///
  /// In en, this message translates to:
  /// **'Invalid current password.'**
  String get backendInvalidCurrentPassword;

  /// Backend invalid date format error
  ///
  /// In en, this message translates to:
  /// **'Invalid date format. Use YYYY-MM-DD.'**
  String get backendInvalidDateFormat;

  /// Backend date not in history error
  ///
  /// In en, this message translates to:
  /// **'This date is not yet in history.'**
  String get backendDateNotInHistory;

  /// Backend no song for history date error
  ///
  /// In en, this message translates to:
  /// **'No song found for this date.'**
  String get backendNoSongFoundForDate;

  /// Backend no pack track for date error
  ///
  /// In en, this message translates to:
  /// **'No pack track found for this date.'**
  String get backendNoPackTrackForDate;

  /// Backend invalid credentials error
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password.'**
  String get backendInvalidCredentials;

  /// Generic network error prefix
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get backendNetworkError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
