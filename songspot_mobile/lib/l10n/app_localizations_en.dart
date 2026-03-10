// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SongSpot';

  @override
  String get loading => 'Loading...';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get save => 'Save';

  @override
  String get submit => 'Submit';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get logout => 'Logout';

  @override
  String get logoutConfirmTitle => 'Logout';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to logout?';

  @override
  String get createRoom => 'Create New Room';

  @override
  String get joinRoom => 'Join a Room';

  @override
  String get myRooms => 'My Rooms';

  @override
  String get noRoomsYet => 'No rooms yet';

  @override
  String get noRoomsHint => 'Create or join a room to start playing!';

  @override
  String get enterRoomCode => 'Enter room code';

  @override
  String members(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString members',
      one: '1 member',
    );
    return '$_temp0';
  }

  @override
  String get loginTitle => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to continue playing';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Login';

  @override
  String get noAccountPrompt => 'Don\'t have an account?';

  @override
  String get registerLink => 'Register';

  @override
  String get registerTitle => 'Create account';

  @override
  String get registerSubtitle => 'Join SongSpot and start guessing';

  @override
  String get usernameLabel => 'Username';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get registerButton => 'Create account';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get loginLink => 'Login';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAccount => 'Account';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsSectionAccessibility => 'Accessibility';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsSectionMyData => 'My Data';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsChangeEmail => 'Change email';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsDailySongNotifications => 'Daily song notifications';

  @override
  String get settingsMessageNotifications => 'Message notifications';

  @override
  String get settingsAccessibility => 'Accessibility';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsExportData => 'Export my data';

  @override
  String get settingsExportDataSubtitle =>
      'Download a copy of all your personal data';

  @override
  String get settingsDeleteAccount => 'Delete my account';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Permanently delete your account and all data';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsManageAdConsent => 'Manage Ad Consent';

  @override
  String get settingsManageAdConsentSubtitle =>
      'Update your ad privacy choices (GDPR)';

  @override
  String get settingsTermsOfService => 'Terms of Service';

  @override
  String get settingsSectionShop => 'Shop';

  @override
  String get settingsCouldNotOpenLink => 'Could not open link';

  @override
  String get settingsBackLabel => 'Back';

  @override
  String get settingsNoAdsPassTitle => 'No Ads Pass';

  @override
  String settingsNoAdsActivationPrompt(num coins, num days) {
    return 'Spend $coins coins to disable ads for $days days?';
  }

  @override
  String get settingsActivate => 'Activate';

  @override
  String get settingsNoAdsActivated => 'No ads activated';

  @override
  String settingsNoAdsTitle(num days) {
    return 'No Ads ($days days)';
  }

  @override
  String settingsExtendNoAdsTitle(num days) {
    return 'Extend No Ads ($days days)';
  }

  @override
  String settingsNoAdsActiveUntil(String date) {
    return 'Active until $date';
  }

  @override
  String settingsNoAdsSpendHint(num coins, num days) {
    return 'Spend $coins coins to disable ads for $days days';
  }

  @override
  String get settingsNotActive => 'Not active';

  @override
  String get adConsentUpdated => 'Ad consent preferences updated.';

  @override
  String get adConsentNotRequired =>
      'Ad privacy options are not required in your region.';

  @override
  String get adConsentError => 'Could not open ad privacy options right now.';

  @override
  String get accessibilityTitle => 'Accessibility';

  @override
  String get accessibilityTextSize => 'Text size';

  @override
  String get accessibilityTextSizePreview => 'Preview text at this size';

  @override
  String get accessibilityTextSizeSmall => 'Small';

  @override
  String get accessibilityTextSizeLarge => 'Large';

  @override
  String get accessibilityReduceAnimations => 'Reduce animations';

  @override
  String get accessibilityReduceAnimationsSubtitle =>
      'Minimize motion throughout the app';

  @override
  String get accessibilityHighContrast => 'High contrast';

  @override
  String get accessibilityHighContrastSubtitle =>
      'Increase color contrast for readability';

  @override
  String get accessibilityColorBlindness => 'Color blindness mode';

  @override
  String get accessibilityColorBlindnessNone => 'None';

  @override
  String get accessibilityColorBlindnessDeuteranopia =>
      'Deuteranopia (red-green)';

  @override
  String get accessibilityColorBlindnessProtanopia => 'Protanopia (red)';

  @override
  String get accessibilityColorBlindnessTritanopia =>
      'Tritanopia (blue-yellow)';

  @override
  String get accessibilityEnhancedScreenReader => 'Enhanced screen reader';

  @override
  String get accessibilityEnhancedScreenReaderSubtitle =>
      'Add more descriptive labels for VoiceOver / TalkBack';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get changeEmailTitle => 'Change email';

  @override
  String get changeEmailCurrentPassword => 'Current password';

  @override
  String get changeEmailNewEmail => 'New email address';

  @override
  String get changeEmailButton => 'Update email';

  @override
  String get changeEmailSuccess => 'Email updated successfully';

  @override
  String get changePasswordTitle => 'Change password';

  @override
  String get changePasswordCurrent => 'Current password';

  @override
  String get changePasswordNew => 'New password';

  @override
  String get changePasswordConfirm => 'Confirm new password';

  @override
  String get changePasswordButton => 'Update password';

  @override
  String get changePasswordSuccess => 'Password updated. Please log in again.';

  @override
  String get myDataTitle => 'My Data';

  @override
  String get myDataExportTitle => 'Export your data';

  @override
  String get myDataExportDescription =>
      'Download a copy of all your personal data including your profile, game history, messages, and coin transactions.';

  @override
  String get myDataExportButton => 'Export my data';

  @override
  String get myDataDeleteTitle => 'Delete your account';

  @override
  String get myDataDeleteDescription =>
      'Permanently delete your account and all associated data. This action cannot be undone.';

  @override
  String get myDataDeleteButton => 'Delete my account';

  @override
  String get myDataDeleteConfirmTitle => 'Delete account';

  @override
  String get myDataDeleteConfirmMessage =>
      'This will permanently delete your account and all your data. Enter your password to confirm.';

  @override
  String get myDataDeleteConfirmButton => 'Delete permanently';

  @override
  String get invalidPassword => 'Invalid password';

  @override
  String get invalidEmail => 'Invalid email address';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get undoAction => 'Undo';

  @override
  String get userFallback => 'User';

  @override
  String get dailyStreakTooltip => 'Daily streak';

  @override
  String get coinsTooltip => 'Coins';

  @override
  String get pleaseEnterRoomCode => 'Please enter a room code';

  @override
  String get finishOrUndoCurrentRoomDeletion =>
      'Finish or undo the current room deletion first.';

  @override
  String get leftRoomHostTransferred => 'Left room. Host transferred.';

  @override
  String get roomRemoved => 'Room removed.';

  @override
  String get roomDeletionCancelled => 'Deletion cancelled.';

  @override
  String get deleteLabel => 'Delete';

  @override
  String get couldNotDeleteRoom => 'Could not delete room.';

  @override
  String get coinShopTitle => 'Coin Shop';

  @override
  String get adNotReadyTryAgain =>
      'Ad not ready yet. Please try again in a moment.';

  @override
  String get storeNotAvailableOnDevice => 'Store not available on this device.';

  @override
  String get productsNotFoundStoreMessage =>
      'Products not found in store. Make sure in-app products are created and set to Active in App Store Connect / Play Console.';

  @override
  String get getMoreCoinsTitle => 'Get more coins';

  @override
  String get useCoinsToUnlockHint =>
      'Use coins to unlock song packs and hints.';

  @override
  String get processingPayment => 'Processing payment...';

  @override
  String get pleaseDontCloseApp => 'Please don\'t close the app';

  @override
  String get yourBalance => 'Your balance';

  @override
  String coinsAmount(num count) {
    return '$count coins';
  }

  @override
  String get freeBonusCoinsTitle => 'Free Bonus Coins';

  @override
  String watchRewardedAdClaimCoins(num coins) {
    return 'Watch a rewarded ad to claim +$coins coins.';
  }

  @override
  String get checkingDailyLimit => 'Checking daily limit...';

  @override
  String get dailyLimitUnavailable => 'Daily limit unavailable right now.';

  @override
  String remainingTodayStatus(num remaining, num cap) {
    return 'Remaining today: $remaining / $cap';
  }

  @override
  String get dailyLimitReached => 'Daily Limit Reached';

  @override
  String get watchAdLabel => 'Watch Ad';

  @override
  String rewardCoinsAddedToBalance(num coins) {
    return '+$coins coins added to your balance.';
  }

  @override
  String coinsAddedSuccess(num coins) {
    return '+$coins coins added!';
  }

  @override
  String get gamePlayingSnippet => '🔊 Playing...';

  @override
  String get gamePlaySnippet => 'Play Snippet';

  @override
  String gameSnippetLabel(num number) {
    return 'Snippet $number';
  }

  @override
  String gamePointsLabel(num points) {
    return '$points points';
  }

  @override
  String get gameMakeYourGuess => 'Make Your Guess';

  @override
  String get gameSongTitleHint => 'Start typing song title...';

  @override
  String get gameSongTitleLabel => 'Song Title';

  @override
  String get gameSkip => 'Skip';

  @override
  String get gameSubmitGuess => 'Submit Guess';

  @override
  String gameGuessesMade(num count) {
    return 'Guesses made: $count';
  }

  @override
  String get gameRetryUnlocked =>
      'Second chance unlocked. Submit another guess.';

  @override
  String get gameWatchAdForRetry => 'Watch Ad for Retry';

  @override
  String gameSpendCoinsForFinalChance(num coins) {
    return 'Spend $coins Coins for Final Chance';
  }

  @override
  String get gameRetryWatchAdSubtitle =>
      'You reached the last snippet. Watch one rewarded ad to unlock a second chance.';

  @override
  String get gameRetryUseCoinsSubtitle =>
      'Use coins to unlock one final guess before results.';

  @override
  String get gameUseRewardForSecondChance => 'Use Reward for Second Chance';

  @override
  String get gameExtraChanceTitle => 'Extra Chance';

  @override
  String get gameSkipExtraChanceShowResults =>
      'Skip Extra Chance and Show Results';

  @override
  String get gameHintsTitle => 'Hints';

  @override
  String get gameHintGenre => 'Genre';

  @override
  String get gameHintDecade => 'Decade';

  @override
  String get gameHintArtist => 'Artist';

  @override
  String get gameSelectSongFromResults =>
      'Please select a song from the search results';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatNoMessagesYet => 'No messages yet';

  @override
  String get chatStartConversation => 'Start the conversation!';

  @override
  String get chatYou => 'You';

  @override
  String get chatTypeMessageHint => 'Type a message...';

  @override
  String get packSearchSongTitleOrArtist => 'Search song title or artist';

  @override
  String get packSkipInstrument => 'Skip Instrument';

  @override
  String get packPlayStems => 'Play Stems';

  @override
  String packStageLabel(num number) {
    return 'Stage $number';
  }

  @override
  String packPointsSoFar(num points) {
    return '$points points so far';
  }

  @override
  String get packPreparingChallenge => 'Preparing your challenge...';

  @override
  String get packPreparingChallengeSubtitle => 'This may take a moment';

  @override
  String get packStageDrums => 'Drums';

  @override
  String get packStageBass => 'Bass';

  @override
  String get packStageOther => 'Other';

  @override
  String get packStageVocals => 'Vocals';

  @override
  String get packStemsGeneratingTryAgain =>
      'Stems are being generated. Try again in a moment.';

  @override
  String get packNoStemsAvailableForStage =>
      'No stems available for this stage';

  @override
  String packFailedToPlayStems(String error) {
    return 'Failed to play stems: $error';
  }

  @override
  String get packCompleted => 'Pack completed!';

  @override
  String get packFailed => 'Pack failed';

  @override
  String packTotalPoints(num points) {
    return 'Total points: $points';
  }

  @override
  String get packResultsTitle => 'Today\'s Results';

  @override
  String get packNoOtherPlayersCompleted =>
      'No other players have completed this pack yet';

  @override
  String packStageCompletedAt(num stage, String time) {
    return 'Stage $stage - $time';
  }

  @override
  String get dailyResultNoOtherPlayersCompleted =>
      'No other players have guessed yet';

  @override
  String dailyResultSnippetCompletedAt(num snippet, String time) {
    return 'Snippet $snippet - $time';
  }

  @override
  String dailyResultNotGuessedAt(String time) {
    return 'Did not guess - $time';
  }

  @override
  String dailyResultPointsSnippet(num points, num snippet) {
    return '+$points points (Snippet $snippet)';
  }

  @override
  String get backendRoomLimitReached =>
      'Room limit reached. Delete or leave one room before creating another.';

  @override
  String backendRoomLimitReachedWithLimit(num maxRooms) {
    return 'Room limit reached ($maxRooms). Delete or leave one room before creating another.';
  }

  @override
  String get backendDailyRoomCreationLimitReached =>
      'Daily room creation limit reached. Try again tomorrow.';

  @override
  String backendDailyRoomCreationLimitReachedWithLimit(num dailyLimit) {
    return 'Daily room creation limit reached ($dailyLimit). Try again tomorrow.';
  }

  @override
  String get backendAlreadyInRoom => 'You are already in this room.';

  @override
  String get backendNotInRoom => 'You are not in this room.';

  @override
  String get backendOnlyHostCanRenameRoom =>
      'Only the host can rename the room.';

  @override
  String get backendMustBeInRoomToPlayGame =>
      'You must be in a room to play this game.';

  @override
  String get backendRoomNotFound => 'Room not found.';

  @override
  String get backendInsufficientCoins => 'Insufficient coins.';

  @override
  String backendInsufficientCoinsWithCost(num requiredCoins) {
    return 'Insufficient coins. You need $requiredCoins coins.';
  }

  @override
  String get backendNoRetriesRemaining => 'No retries remaining.';

  @override
  String get backendRetryAfterLastSnippetOnly =>
      'Retry is only available after the last snippet.';

  @override
  String get backendRetryAlreadyActive => 'Second chance is already active.';

  @override
  String get backendRetryNotPendingUnlock =>
      'Second chance is not available right now.';

  @override
  String backendInvalidRetryAction(String expectedAction) {
    return 'Invalid retry action. Expected: $expectedAction.';
  }

  @override
  String get backendInvalidRetryActionUnknown => 'Invalid retry action.';

  @override
  String get backendGameAlreadyCompleted => 'Game already completed.';

  @override
  String get backendNoActiveGameSession => 'No active game session.';

  @override
  String get backendNoSongAvailableToday => 'No song available for today.';

  @override
  String get backendPackNotOwnedByRoom => 'This pack is not owned by the room.';

  @override
  String get backendPackHasNoTracks => 'This pack has no tracks.';

  @override
  String get backendNoActivePackSession => 'No active pack session.';

  @override
  String get backendPackAlreadyCompleted => 'Pack already completed.';

  @override
  String get backendTrackNotFound => 'Track not found.';

  @override
  String get backendAlreadyGuessedForStage =>
      'You already guessed for this stage.';

  @override
  String get backendRoomIdRequired => 'Room is required.';

  @override
  String get backendInvalidPassword => 'Invalid password.';

  @override
  String get backendInvalidCurrentPassword => 'Invalid current password.';

  @override
  String get backendInvalidDateFormat => 'Invalid date format. Use YYYY-MM-DD.';

  @override
  String get backendDateNotInHistory => 'This date is not yet in history.';

  @override
  String get backendNoSongFoundForDate => 'No song found for this date.';

  @override
  String get backendNoPackTrackForDate => 'No pack track found for this date.';

  @override
  String get backendInvalidCredentials => 'Invalid email or password.';

  @override
  String get backendRefreshTokenRequired => 'Refresh token is required.';

  @override
  String get backendInvalidOrExpiredRefreshToken =>
      'Refresh token is invalid or expired.';

  @override
  String get backendInvalidToken => 'Token is invalid.';

  @override
  String get backendMissingRequiredFields => 'Missing required fields.';

  @override
  String get backendInvalidStore => 'Invalid store.';

  @override
  String get backendPurchaseProcessing => 'Purchase is being processed.';

  @override
  String backendUnknownOrInactiveProduct(String productId) {
    return 'Unknown or inactive product: $productId.';
  }

  @override
  String get backendUnknownOrInactiveProductUnknown =>
      'Unknown or inactive product.';

  @override
  String get backendReceiptVerificationFailed => 'Receipt verification failed.';

  @override
  String get backendNetworkError => 'Network error';
}
