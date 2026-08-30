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

  /// Forgot password link on the login screen
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordLink;

  /// Prompt shown when forgot password is tapped without a valid email
  ///
  /// In en, this message translates to:
  /// **'Enter your email address first.'**
  String get forgotPasswordEnterEmail;

  /// Success message after requesting a password reset email
  ///
  /// In en, this message translates to:
  /// **'If an account exists for this email, a reset email has been sent.'**
  String get forgotPasswordEmailSent;

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

  /// Fallback login failure message
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// Fallback registration failure message
  ///
  /// In en, this message translates to:
  /// **'Registration failed'**
  String get registrationFailed;

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

  /// Shown when external URL cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get settingsCouldNotOpenLink;

  /// Semantic label for back button
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBackLabel;

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

  /// Invalid email error
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmail;

  /// Username minimum length validation
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get usernameMinLength;

  /// Password minimum length validation
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMinLength;

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

  /// Label for the mix mode
  ///
  /// In en, this message translates to:
  /// **'Daily Mix'**
  String get dailyModeMixLabel;

  /// Label for the genre mode
  ///
  /// In en, this message translates to:
  /// **'Genre Mode'**
  String get dailyModeGenreLabel;

  /// Label for the decade mode
  ///
  /// In en, this message translates to:
  /// **'Decade Mode'**
  String get dailyModeDecadeLabel;

  /// Label for the hardcore mode
  ///
  /// In en, this message translates to:
  /// **'Hardcore'**
  String get dailyModeHardcoreLabel;

  /// Subtitle for the mix mode
  ///
  /// In en, this message translates to:
  /// **'Fully random song for everyone today'**
  String get dailyModeMixSubtitle;

  /// Subtitle for the genre mode
  ///
  /// In en, this message translates to:
  /// **'Fixed genre for everyone today'**
  String get dailyModeGenreSubtitle;

  /// Subtitle for the decade mode
  ///
  /// In en, this message translates to:
  /// **'Fixed decade for everyone today'**
  String get dailyModeDecadeSubtitle;

  /// Subtitle for the hardcore mode
  ///
  /// In en, this message translates to:
  /// **'Same daily song, but no hints and no retries'**
  String get dailyModeHardcoreSubtitle;

  /// Subtitle when a specific daily lane is active
  ///
  /// In en, this message translates to:
  /// **'Today\'s lane: {name}'**
  String dailyModeLaneSubtitle(String name);

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

  /// Backend invalid credentials error
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password.'**
  String get backendInvalidCredentials;

  /// Backend password reset email unavailable error
  ///
  /// In en, this message translates to:
  /// **'Password reset email is currently unavailable.'**
  String get backendPasswordResetUnavailable;

  /// Backend missing refresh token error
  ///
  /// In en, this message translates to:
  /// **'Refresh token is required.'**
  String get backendRefreshTokenRequired;

  /// Backend invalid or expired refresh token error
  ///
  /// In en, this message translates to:
  /// **'Refresh token is invalid or expired.'**
  String get backendInvalidOrExpiredRefreshToken;

  /// Backend invalid access token error
  ///
  /// In en, this message translates to:
  /// **'Token is invalid.'**
  String get backendInvalidToken;

  /// Backend missing required fields error
  ///
  /// In en, this message translates to:
  /// **'Missing required fields.'**
  String get backendMissingRequiredFields;

  /// Generic network error prefix
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get backendNetworkError;

  /// No description provided for @signInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get signInRequired;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @gameEndSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'End session?'**
  String get gameEndSessionTitle;

  /// No description provided for @gameEndSessionMessage.
  ///
  /// In en, this message translates to:
  /// **'Your progress will be submitted.'**
  String get gameEndSessionMessage;

  /// No description provided for @gameEndSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get gameEndSessionConfirm;

  /// No description provided for @gamePlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing...'**
  String get gamePlaying;

  /// No description provided for @gamePlayWithDuration.
  ///
  /// In en, this message translates to:
  /// **'Play {duration}'**
  String gamePlayWithDuration(String duration);

  /// No description provided for @gameSongInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type song title...'**
  String get gameSongInputHint;

  /// No description provided for @gameGiveUp.
  ///
  /// In en, this message translates to:
  /// **'Give up'**
  String get gameGiveUp;

  /// No description provided for @gameCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get gameCorrect;

  /// No description provided for @gameWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get gameWrong;

  /// No description provided for @gameSeeResults.
  ///
  /// In en, this message translates to:
  /// **'See Results'**
  String get gameSeeResults;

  /// No description provided for @gameNextButton.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get gameNextButton;

  /// Shortcut reminder under the guess box on keyboard/pointer layouts.
  ///
  /// In en, this message translates to:
  /// **'↑ ↓ browse · Enter picks · Esc clears'**
  String get gameKeyboardHintGuess;

  /// Shortcut reminder next to the next-song button on keyboard/pointer layouts.
  ///
  /// In en, this message translates to:
  /// **'Enter continues'**
  String get gameKeyboardHintNext;

  /// No description provided for @sessionEndHeadlineCleared.
  ///
  /// In en, this message translates to:
  /// **'You cleared it!'**
  String get sessionEndHeadlineCleared;

  /// No description provided for @sessionEndHeadlineOutOfLives.
  ///
  /// In en, this message translates to:
  /// **'Out of lives!'**
  String get sessionEndHeadlineOutOfLives;

  /// No description provided for @sessionEndHeadlineEnded.
  ///
  /// In en, this message translates to:
  /// **'Session ended'**
  String get sessionEndHeadlineEnded;

  /// No description provided for @sessionEndHeadlineOnFire.
  ///
  /// In en, this message translates to:
  /// **'On fire!'**
  String get sessionEndHeadlineOnFire;

  /// No description provided for @sessionEndHeadlineNiceRun.
  ///
  /// In en, this message translates to:
  /// **'Nice run!'**
  String get sessionEndHeadlineNiceRun;

  /// No description provided for @sessionEndHeadlineGoodTry.
  ///
  /// In en, this message translates to:
  /// **'Good try!'**
  String get sessionEndHeadlineGoodTry;

  /// No description provided for @sessionEndStatScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get sessionEndStatScore;

  /// No description provided for @sessionEndStatSongs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get sessionEndStatSongs;

  /// No description provided for @sessionEndPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play again'**
  String get sessionEndPlayAgain;

  /// No description provided for @sessionEndChangeCategory.
  ///
  /// In en, this message translates to:
  /// **'Change category'**
  String get sessionEndChangeCategory;

  /// No description provided for @sessionEndBackToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get sessionEndBackToHome;

  /// No description provided for @categorySignInForFavourites.
  ///
  /// In en, this message translates to:
  /// **'You need an account to save favourite artists.'**
  String get categorySignInForFavourites;

  /// No description provided for @categoryStartRun.
  ///
  /// In en, this message translates to:
  /// **'Start Run'**
  String get categoryStartRun;

  /// No description provided for @categoryChooseCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get categoryChooseCategory;

  /// No description provided for @categoryTabGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get categoryTabGenre;

  /// No description provided for @categoryTabArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get categoryTabArtist;

  /// No description provided for @categorySearchArtistHint.
  ///
  /// In en, this message translates to:
  /// **'Search artist...'**
  String get categorySearchArtistHint;

  /// No description provided for @categoryNoArtistsFound.
  ///
  /// In en, this message translates to:
  /// **'No artists found'**
  String get categoryNoArtistsFound;

  /// No description provided for @categorySearchArtistAbove.
  ///
  /// In en, this message translates to:
  /// **'Search for an artist above'**
  String get categorySearchArtistAbove;

  /// No description provided for @categoryYourFavourites.
  ///
  /// In en, this message translates to:
  /// **'Your favourites'**
  String get categoryYourFavourites;

  /// No description provided for @categoryTrending.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get categoryTrending;

  /// No description provided for @homeGuest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get homeGuest;

  /// No description provided for @homePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get homePlay;

  /// No description provided for @homeSoloLabel.
  ///
  /// In en, this message translates to:
  /// **'Solo'**
  String get homeSoloLabel;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Test your music knowledge'**
  String get homeTagline;

  /// No description provided for @homeSignInToPlay.
  ///
  /// In en, this message translates to:
  /// **'Sign in to play'**
  String get homeSignInToPlay;

  /// Label above the difficulty picker in the pre-game panel.
  ///
  /// In en, this message translates to:
  /// **'Difficulty'**
  String get categoryDifficulty;

  /// Track count on a genre card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 song} other{{count} songs}}'**
  String categorySongCount(int count);

  /// Body of the dialog shown when a guest taps the 1v1 card.
  ///
  /// In en, this message translates to:
  /// **'1v1 needs an account. Sign in or create one to play against someone else.'**
  String get homeDuelSignInPrompt;

  /// Sublabel on the solo mode card on the home screen.
  ///
  /// In en, this message translates to:
  /// **'One track at a time, three lives'**
  String get homeSoloSublabel;

  /// Sublabel on the 1v1 mode card on the home screen.
  ///
  /// In en, this message translates to:
  /// **'Race someone else, round for round'**
  String get homeDuelSublabel;

  /// No description provided for @homeComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get homeComingSoon;

  /// No description provided for @homeGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi, {username}'**
  String homeGreeting(String username);

  /// No description provided for @homeStatBestScore.
  ///
  /// In en, this message translates to:
  /// **'Best score'**
  String get homeStatBestScore;

  /// No description provided for @homeStatBestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best streak'**
  String get homeStatBestStreak;

  /// No description provided for @homeStatSongs.
  ///
  /// In en, this message translates to:
  /// **'Songs played'**
  String get homeStatSongs;

  /// No description provided for @homeDeezerCredits.
  ///
  /// In en, this message translates to:
  /// **'Music previews powered by Deezer'**
  String get homeDeezerCredits;

  /// No description provided for @loginContinueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as guest'**
  String get loginContinueAsGuest;

  /// No description provided for @settingsSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in / Create account'**
  String get settingsSignInPrompt;

  /// No description provided for @sessionEndStatStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get sessionEndStatStreak;

  /// No description provided for @sessionEndStatAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get sessionEndStatAccuracy;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'SongSpot'**
  String get appTitle;

  /// No description provided for @changeEmailSuccess.
  ///
  /// In en, this message translates to:
  /// **'Email updated successfully'**
  String get changeEmailSuccess;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated. Please log in again.'**
  String get changePasswordSuccess;

  /// Matchmaking searching state title
  ///
  /// In en, this message translates to:
  /// **'Finding opponent...'**
  String get duelFindingOpponent;

  /// ELO card label in duel lobby
  ///
  /// In en, this message translates to:
  /// **'Your ELO'**
  String get duelYourElo;

  /// ELO rank and win/loss/draw stats
  ///
  /// In en, this message translates to:
  /// **'Rank #{rank}  •  {wins}W {losses}L {draws}D'**
  String duelRankStats(int rank, int wins, int losses, int draws);

  /// Info section header in duel lobby
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get duelHowItWorks;

  /// Duel lobby info row 1
  ///
  /// In en, this message translates to:
  /// **'Same song, same round for both players'**
  String get duelInfoSameSong;

  /// Duel lobby info row 2
  ///
  /// In en, this message translates to:
  /// **'Guess early = more points (up to 100)'**
  String get duelInfoGuessEarly;

  /// Duel lobby info row 3
  ///
  /// In en, this message translates to:
  /// **'Extend snippet for more confidence, fewer points'**
  String get duelInfoExtendSnippet;

  /// Duel lobby info row 4
  ///
  /// In en, this message translates to:
  /// **'5 rounds — highest score wins ELO'**
  String get duelInfoFiveRounds;

  /// Primary CTA button in duel lobby
  ///
  /// In en, this message translates to:
  /// **'Find Match'**
  String get duelFindMatch;

  /// Score separator in duel game app bar
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get duelVs;

  /// Snippet duration label
  ///
  /// In en, this message translates to:
  /// **'{seconds}s snippet'**
  String duelSnippetLabel(int seconds);

  /// Overlay text while audio is buffering
  ///
  /// In en, this message translates to:
  /// **'Loading audio...'**
  String get duelLoadingAudio;

  /// Overlay text after local audio is ready, waiting for opponent
  ///
  /// In en, this message translates to:
  /// **'Waiting for opponent...'**
  String get duelWaitingOpponent;

  /// Track card status when snippet is playing
  ///
  /// In en, this message translates to:
  /// **'Playing {duration}...'**
  String duelPlayingSnippet(String duration);

  /// Track card idle status
  ///
  /// In en, this message translates to:
  /// **'Tap to listen · {duration}'**
  String duelTapToListen(String duration);

  /// Extend snippet button label
  ///
  /// In en, this message translates to:
  /// **'Extend to {duration}'**
  String duelExtendTo(String duration);

  /// Guess text field hint
  ///
  /// In en, this message translates to:
  /// **'Search for a song...'**
  String get duelSearchHint;

  /// Badge shown when opponent has submitted their guess
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get duelOpponentSubmitted;

  /// Banner after player submits, waiting for opponent
  ///
  /// In en, this message translates to:
  /// **'Submitted — waiting for opponent...'**
  String get duelYouSubmittedWaiting;

  /// Points abbreviation in snippet controls
  ///
  /// In en, this message translates to:
  /// **'pts'**
  String get duelPts;

  /// Round result label when guess was incorrect
  ///
  /// In en, this message translates to:
  /// **'Wrong!'**
  String get duelWrong;

  /// Footer in round result overlay
  ///
  /// In en, this message translates to:
  /// **'Next round starting...'**
  String get duelNextRound;

  /// Label for the local player in score displays
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get duelYou;

  /// Match result: victory
  ///
  /// In en, this message translates to:
  /// **'You Win!'**
  String get duelWin;

  /// Match result: defeat
  ///
  /// In en, this message translates to:
  /// **'You Lost'**
  String get duelLost;

  /// Match result: draw
  ///
  /// In en, this message translates to:
  /// **'Draw!'**
  String get duelDraw;

  /// New ELO display after match
  ///
  /// In en, this message translates to:
  /// **'New ELO: {elo}'**
  String duelNewElo(int elo);

  /// Section header in match result screen
  ///
  /// In en, this message translates to:
  /// **'Match Summary'**
  String get duelMatchSummary;

  /// Round number label
  ///
  /// In en, this message translates to:
  /// **'Round {round}'**
  String duelRoundLabel(int round);

  /// Play again button in match result screen
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get duelPlayAgain;

  /// Back to home button in match result screen
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get duelBackToHome;

  /// Privacy section header in settings
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsSectionPrivacy;

  /// Analytics opt-in switch in settings
  ///
  /// In en, this message translates to:
  /// **'Share usage statistics'**
  String get settingsAnalytics;

  /// Explanation under the analytics switch
  ///
  /// In en, this message translates to:
  /// **'Helps us see which genres and difficulties work. Never includes your guesses or personal data.'**
  String get settingsAnalyticsSubtitle;
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
