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

  /// Settings tile to open UMP privacy options form
  ///
  /// In en, this message translates to:
  /// **'Manage Ad Consent'**
  String get settingsManageAdConsent;

  /// Subtitle for ad consent settings tile
  ///
  /// In en, this message translates to:
  /// **'Update your ad privacy choices (GDPR)'**
  String get settingsManageAdConsentSubtitle;

  /// Terms of service tile
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTermsOfService;

  /// Shop section header in settings
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get settingsSectionShop;

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

  /// No-ads activation dialog title
  ///
  /// In en, this message translates to:
  /// **'No Ads Pass'**
  String get settingsNoAdsPassTitle;

  /// No-ads activation dialog message
  ///
  /// In en, this message translates to:
  /// **'Spend {coins} coins to disable ads for {days} days?'**
  String settingsNoAdsActivationPrompt(num coins, num days);

  /// Activate action label
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get settingsActivate;

  /// No-ads activation success snackbar
  ///
  /// In en, this message translates to:
  /// **'No ads activated'**
  String get settingsNoAdsActivated;

  /// No-ads tile title when not active
  ///
  /// In en, this message translates to:
  /// **'No Ads ({days} days)'**
  String settingsNoAdsTitle(num days);

  /// No-ads tile title when already active
  ///
  /// In en, this message translates to:
  /// **'Extend No Ads ({days} days)'**
  String settingsExtendNoAdsTitle(num days);

  /// No-ads subtitle when active
  ///
  /// In en, this message translates to:
  /// **'Active until {date}'**
  String settingsNoAdsActiveUntil(String date);

  /// No-ads subtitle when inactive
  ///
  /// In en, this message translates to:
  /// **'Spend {coins} coins to disable ads for {days} days'**
  String settingsNoAdsSpendHint(num coins, num days);

  /// Fallback no-ads state label
  ///
  /// In en, this message translates to:
  /// **'Not active'**
  String get settingsNotActive;

  /// Shown after user updates ad consent options
  ///
  /// In en, this message translates to:
  /// **'Ad consent preferences updated.'**
  String get adConsentUpdated;

  /// Shown when privacy options entry is not required by UMP
  ///
  /// In en, this message translates to:
  /// **'Ad privacy options are not required in your region.'**
  String get adConsentNotRequired;

  /// Shown when UMP privacy options form cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Could not open ad privacy options right now.'**
  String get adConsentError;

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

  /// Pack list screen title
  ///
  /// In en, this message translates to:
  /// **'Song Packs'**
  String get packListTitle;

  /// Pack list heading
  ///
  /// In en, this message translates to:
  /// **'Browse packs'**
  String get packBrowseTitle;

  /// Pack category filter for all packs
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get packFilterAll;

  /// Pack list coin helper text
  ///
  /// In en, this message translates to:
  /// **'Need more coins?'**
  String get packNeedMoreCoins;

  /// Pack list CTA to open coin shop
  ///
  /// In en, this message translates to:
  /// **'Get Coins'**
  String get packGetCoins;

  /// Pack price label for free packs
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get packPriceFree;

  /// Pack price label in coins
  ///
  /// In en, this message translates to:
  /// **'{coins} coins'**
  String packCoinsPrice(num coins);

  /// Current active day progress for a pack
  ///
  /// In en, this message translates to:
  /// **'Day {day} of {totalDays}'**
  String packProgressDay(num day, num totalDays);

  /// Pack state text when active
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get packStateInProgress;

  /// Pack state text when completed
  ///
  /// In en, this message translates to:
  /// **'Finished in this room'**
  String get packStateFinishedInRoom;

  /// Pack state text when available to activate
  ///
  /// In en, this message translates to:
  /// **'Ready now'**
  String get packStateReadyNow;

  /// Pack state text when blocked by another active pack
  ///
  /// In en, this message translates to:
  /// **'Unavailable now'**
  String get packStateAfterActivePack;

  /// Pack status tag when active
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get packTagInProgress;

  /// Pack status tag when completed
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get packTagFinished;

  /// Pack status tag when can activate
  ///
  /// In en, this message translates to:
  /// **'Ready Now'**
  String get packTagReadyNow;

  /// Pack status tag when blocked by another active pack
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get packTagAfterActivePack;

  /// Primary pack action for free unowned packs
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get packActionUnlock;

  /// Primary pack action for paid unowned packs
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get packActionBuy;

  /// Disabled pack action label while pack is active
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get packActionInProgress;

  /// Disabled pack action label when pack is completed
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get packActionFinished;

  /// Primary pack action to activate an owned pack
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get packActionActivate;

  /// Disabled pack action label when another pack is active
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get packActionLater;

  /// Pack activation success message
  ///
  /// In en, this message translates to:
  /// **'Pack activated successfully'**
  String get packActivatedSuccessfully;

  /// Pack purchase success message
  ///
  /// In en, this message translates to:
  /// **'Pack unlocked. Activate it when you are ready.'**
  String get packUnlockedActivateWhenReady;

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

  /// Game CTA while snippet audio is currently playing
  ///
  /// In en, this message translates to:
  /// **'🔊 Playing...'**
  String get gamePlayingSnippet;

  /// Game CTA to play current snippet
  ///
  /// In en, this message translates to:
  /// **'Play Snippet'**
  String get gamePlaySnippet;

  /// Current snippet indicator label
  ///
  /// In en, this message translates to:
  /// **'Snippet {number}'**
  String gameSnippetLabel(num number);

  /// Possible points label
  ///
  /// In en, this message translates to:
  /// **'{points} points'**
  String gamePointsLabel(num points);

  /// Heading above guess form
  ///
  /// In en, this message translates to:
  /// **'Make Your Guess'**
  String get gameMakeYourGuess;

  /// Song autocomplete hint text
  ///
  /// In en, this message translates to:
  /// **'Start typing song title...'**
  String get gameSongTitleHint;

  /// Song autocomplete label text
  ///
  /// In en, this message translates to:
  /// **'Song Title'**
  String get gameSongTitleLabel;

  /// Skip snippet button label
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get gameSkip;

  /// Submit guess button label
  ///
  /// In en, this message translates to:
  /// **'Submit Guess'**
  String get gameSubmitGuess;

  /// Guesses made counter label
  ///
  /// In en, this message translates to:
  /// **'Guesses made: {count}'**
  String gameGuessesMade(num count);

  /// Banner shown when retry is already unlocked
  ///
  /// In en, this message translates to:
  /// **'Second chance unlocked. Submit another guess.'**
  String get gameRetryUnlocked;

  /// Retry CTA for ad-based unlock
  ///
  /// In en, this message translates to:
  /// **'Watch Ad for Retry'**
  String get gameWatchAdForRetry;

  /// Retry CTA for coin-based unlock
  ///
  /// In en, this message translates to:
  /// **'Spend {coins} Coins for Final Chance'**
  String gameSpendCoinsForFinalChance(num coins);

  /// Retry subtitle when next action is ad
  ///
  /// In en, this message translates to:
  /// **'You reached the last snippet. Watch one rewarded ad to unlock a second chance.'**
  String get gameRetryWatchAdSubtitle;

  /// Retry subtitle when next action is coins
  ///
  /// In en, this message translates to:
  /// **'Use coins to unlock one final guess before results.'**
  String get gameRetryUseCoinsSubtitle;

  /// Retry CTA when user has ad-free pass and ad action is required
  ///
  /// In en, this message translates to:
  /// **'Use Reward for Second Chance'**
  String get gameUseRewardForSecondChance;

  /// Retry card title
  ///
  /// In en, this message translates to:
  /// **'Extra Chance'**
  String get gameExtraChanceTitle;

  /// Retry card secondary action label
  ///
  /// In en, this message translates to:
  /// **'Skip Extra Chance and Show Results'**
  String get gameSkipExtraChanceShowResults;

  /// Hints section title
  ///
  /// In en, this message translates to:
  /// **'Hints'**
  String get gameHintsTitle;

  /// Hint chip label for genre
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get gameHintGenre;

  /// Hint chip label for decade
  ///
  /// In en, this message translates to:
  /// **'Decade'**
  String get gameHintDecade;

  /// Hint chip label for artist
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get gameHintArtist;

  /// Generic cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic close label or tooltip
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Label for the pack mode pill in the game switcher
  ///
  /// In en, this message translates to:
  /// **'Pack'**
  String get packModeLabel;

  /// Title for the mode section or modes sheet
  ///
  /// In en, this message translates to:
  /// **'Daily Modes'**
  String get dailyModesTitle;

  /// Short label for the button that opens the modes sheet
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get dailyModesShortLabel;

  /// Intro text for the modes sheet
  ///
  /// In en, this message translates to:
  /// **'Unlock extra lanes for this room without replacing Daily Mix.'**
  String get dailyModesIntro;

  /// Intro text for the room details modes section
  ///
  /// In en, this message translates to:
  /// **'Mix is always free. Contribute with your room to unlock extra daily lanes.'**
  String get dailyModesRoomIntro;

  /// Hint shown below the modes list to indicate scrolling
  ///
  /// In en, this message translates to:
  /// **'Scroll to see all modes'**
  String get dailyModesScrollHint;

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

  /// Price label for a free mode
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get dailyModeFree;

  /// Price label for a paid mode
  ///
  /// In en, this message translates to:
  /// **'{coins} coins'**
  String dailyModeCoinsCost(num coins);

  /// Status text shown when a mode is unlocked
  ///
  /// In en, this message translates to:
  /// **'Unlocked for this room until next reset'**
  String get dailyModeUnlockedUntilReset;

  /// Funding progress text for a mode card
  ///
  /// In en, this message translates to:
  /// **'{progress}/{total} coins • {contributors} contributors'**
  String dailyModeContributionProgress(
    num progress,
    num total,
    num contributors,
  );

  /// Primary action label for a playable mode
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get dailyModePlay;

  /// Primary action label for a previewable mode
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get dailyModePreview;

  /// Action/status label for an unlocked mode
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get dailyModeUnlocked;

  /// Action label to contribute to a mode
  ///
  /// In en, this message translates to:
  /// **'Contribute'**
  String get dailyModeContribute;

  /// Status label when a mode is funded
  ///
  /// In en, this message translates to:
  /// **'Funded'**
  String get dailyModeFunded;

  /// Dialog title for contributing to a mode
  ///
  /// In en, this message translates to:
  /// **'Contribute to {mode}'**
  String dailyModeContributeTitle(String mode);

  /// Helper text showing remaining funding and the user's balance
  ///
  /// In en, this message translates to:
  /// **'{remaining} coins remaining. You currently have {coins} coins.'**
  String dailyModeCoinsRemainingYouHave(num remaining, num coins);

  /// Input label for the contribution amount
  ///
  /// In en, this message translates to:
  /// **'Coins to contribute'**
  String get dailyModeCoinsToContribute;

  /// Quick contribution chip label for a fixed amount
  ///
  /// In en, this message translates to:
  /// **'+{amount}'**
  String dailyModeContributionQuickAmount(num amount);

  /// Quick contribution chip label to fully fund the remaining amount the user can afford
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get dailyModeContributionFill;

  /// Short label for remaining room funding in the contribution sheet
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get dailyModeContributionRemainingLabel;

  /// Short label for the user's current coin balance in the contribution sheet
  ///
  /// In en, this message translates to:
  /// **'Your balance'**
  String get dailyModeContributionBalanceLabel;

  /// Short label showing how much funding remains
  ///
  /// In en, this message translates to:
  /// **'{remaining} left'**
  String dailyModeContributionLeft(num remaining);

  /// Snackbar shown when a contribution succeeds without unlocking the mode
  ///
  /// In en, this message translates to:
  /// **'Contribution sent'**
  String get dailyModeContributionSent;

  /// Snackbar shown when a mode becomes unlocked
  ///
  /// In en, this message translates to:
  /// **'{mode} unlocked for this room'**
  String dailyModeUnlockedForRoom(String mode);

  /// Title for the hardcore rules card
  ///
  /// In en, this message translates to:
  /// **'Hardcore rules'**
  String get dailyModeHardcoreRulesTitle;

  /// Body copy for the hardcore rules card
  ///
  /// In en, this message translates to:
  /// **'This lane disables hints and retry unlocks. One run only.'**
  String get dailyModeHardcoreRulesBody;

  /// Error when submitting without selecting an autocomplete result
  ///
  /// In en, this message translates to:
  /// **'Please select a song from the search results'**
  String get gameSelectSongFromResults;

  /// Chat section title
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// Empty chat title message
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatNoMessagesYet;

  /// Empty chat subtitle message
  ///
  /// In en, this message translates to:
  /// **'Start the conversation!'**
  String get chatStartConversation;

  /// Current user label in chat bubbles
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatYou;

  /// Chat input hint text
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get chatTypeMessageHint;

  /// Pack mode autocomplete hint text
  ///
  /// In en, this message translates to:
  /// **'Search song title or artist'**
  String get packSearchSongTitleOrArtist;

  /// Pack mode skip stage button label
  ///
  /// In en, this message translates to:
  /// **'Skip Instrument'**
  String get packSkipInstrument;

  /// Pack mode play stems button label
  ///
  /// In en, this message translates to:
  /// **'Play Stems'**
  String get packPlayStems;

  /// Pack mode stage label
  ///
  /// In en, this message translates to:
  /// **'Stage {number}'**
  String packStageLabel(num number);

  /// Pack mode points summary
  ///
  /// In en, this message translates to:
  /// **'{points} points so far'**
  String packPointsSoFar(num points);

  /// Pack stems generation status title
  ///
  /// In en, this message translates to:
  /// **'Preparing your challenge...'**
  String get packPreparingChallenge;

  /// Pack stems generation status subtitle
  ///
  /// In en, this message translates to:
  /// **'This may take a moment'**
  String get packPreparingChallengeSubtitle;

  /// Pack stage name for drums stem
  ///
  /// In en, this message translates to:
  /// **'Drums'**
  String get packStageDrums;

  /// Pack stage name for bass stem
  ///
  /// In en, this message translates to:
  /// **'Bass'**
  String get packStageBass;

  /// Pack stage name for other stems
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get packStageOther;

  /// Pack stage name for vocals stem
  ///
  /// In en, this message translates to:
  /// **'Vocals'**
  String get packStageVocals;

  /// Snack when attempting to play stems while generation is still in progress
  ///
  /// In en, this message translates to:
  /// **'Stems are being generated. Try again in a moment.'**
  String get packStemsGeneratingTryAgain;

  /// Snack when no stems were returned for current pack stage
  ///
  /// In en, this message translates to:
  /// **'No stems available for this stage'**
  String get packNoStemsAvailableForStage;

  /// Snack shown when local stem playback fails
  ///
  /// In en, this message translates to:
  /// **'Failed to play stems: {error}'**
  String packFailedToPlayStems(String error);

  /// Pack completion headline
  ///
  /// In en, this message translates to:
  /// **'Pack completed!'**
  String get packCompleted;

  /// Pack failure headline
  ///
  /// In en, this message translates to:
  /// **'Pack failed'**
  String get packFailed;

  /// Pack completion total points
  ///
  /// In en, this message translates to:
  /// **'Total points: {points}'**
  String packTotalPoints(num points);

  /// Pack completion results section title
  ///
  /// In en, this message translates to:
  /// **'Today\'s Results'**
  String get packResultsTitle;

  /// Empty state for pack leaderboard
  ///
  /// In en, this message translates to:
  /// **'No other players have completed this pack yet'**
  String get packNoOtherPlayersCompleted;

  /// Pack leaderboard row subtitle with stage and completion time
  ///
  /// In en, this message translates to:
  /// **'Stage {stage} - {time}'**
  String packStageCompletedAt(num stage, String time);

  /// Empty state for daily results leaderboard
  ///
  /// In en, this message translates to:
  /// **'No other players have guessed yet'**
  String get dailyResultNoOtherPlayersCompleted;

  /// Daily leaderboard row subtitle with snippet and completion time
  ///
  /// In en, this message translates to:
  /// **'Snippet {snippet} - {time}'**
  String dailyResultSnippetCompletedAt(num snippet, String time);

  /// Daily leaderboard row subtitle when the song was not guessed
  ///
  /// In en, this message translates to:
  /// **'Did not guess - {time}'**
  String dailyResultNotGuessedAt(String time);

  /// Daily result success badge with points and snippet number
  ///
  /// In en, this message translates to:
  /// **'+{points} points (Snippet {snippet})'**
  String dailyResultPointsSnippet(num points, num snippet);

  /// Backend room hosted limit error
  ///
  /// In en, this message translates to:
  /// **'Room limit reached. Delete or leave one room before creating another.'**
  String get backendRoomLimitReached;

  /// Backend room hosted limit error with max rooms value
  ///
  /// In en, this message translates to:
  /// **'Room limit reached ({maxRooms}). Delete or leave one room before creating another.'**
  String backendRoomLimitReachedWithLimit(num maxRooms);

  /// Backend daily room creation limit error
  ///
  /// In en, this message translates to:
  /// **'Daily room creation limit reached. Try again tomorrow.'**
  String get backendDailyRoomCreationLimitReached;

  /// Backend daily room creation limit with explicit limit value
  ///
  /// In en, this message translates to:
  /// **'Daily room creation limit reached ({dailyLimit}). Try again tomorrow.'**
  String backendDailyRoomCreationLimitReachedWithLimit(num dailyLimit);

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

  /// Backend room membership required for game actions
  ///
  /// In en, this message translates to:
  /// **'You must be in a room to play this game.'**
  String get backendMustBeInRoomToPlayGame;

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

  /// Backend insufficient coins error with required cost
  ///
  /// In en, this message translates to:
  /// **'Insufficient coins. You need {requiredCoins} coins.'**
  String backendInsufficientCoinsWithCost(num requiredCoins);

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

  /// Backend retry already active error
  ///
  /// In en, this message translates to:
  /// **'Second chance is already active.'**
  String get backendRetryAlreadyActive;

  /// Backend retry not pending unlock error
  ///
  /// In en, this message translates to:
  /// **'Second chance is not available right now.'**
  String get backendRetryNotPendingUnlock;

  /// Backend invalid retry action with expected value
  ///
  /// In en, this message translates to:
  /// **'Invalid retry action. Expected: {expectedAction}.'**
  String backendInvalidRetryAction(String expectedAction);

  /// Backend invalid retry action without expected value
  ///
  /// In en, this message translates to:
  /// **'Invalid retry action.'**
  String get backendInvalidRetryActionUnknown;

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

  /// Backend invalid store identifier error
  ///
  /// In en, this message translates to:
  /// **'Invalid store.'**
  String get backendInvalidStore;

  /// Backend purchase in progress or already processed response
  ///
  /// In en, this message translates to:
  /// **'Purchase is being processed.'**
  String get backendPurchaseProcessing;

  /// Backend unknown or inactive product with product id
  ///
  /// In en, this message translates to:
  /// **'Unknown or inactive product: {productId}.'**
  String backendUnknownOrInactiveProduct(String productId);

  /// Backend unknown or inactive product without product id
  ///
  /// In en, this message translates to:
  /// **'Unknown or inactive product.'**
  String get backendUnknownOrInactiveProductUnknown;

  /// Backend receipt verification failed error
  ///
  /// In en, this message translates to:
  /// **'Receipt verification failed.'**
  String get backendReceiptVerificationFailed;

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
