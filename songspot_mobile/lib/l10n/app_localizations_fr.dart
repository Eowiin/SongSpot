// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'SongSpot';

  @override
  String get loading => 'Chargement...';

  @override
  String get cancel => 'Annuler';

  @override
  String get confirm => 'Confirmer';

  @override
  String get save => 'Enregistrer';

  @override
  String get submit => 'Valider';

  @override
  String get error => 'Erreur';

  @override
  String get success => 'Succès';

  @override
  String get logout => 'Se déconnecter';

  @override
  String get logoutConfirmTitle => 'Déconnexion';

  @override
  String get logoutConfirmMessage =>
      'Êtes-vous sûr de vouloir vous déconnecter ?';

  @override
  String get createRoom => 'Créer une salle';

  @override
  String get joinRoom => 'Rejoindre une salle';

  @override
  String get myRooms => 'Mes salles';

  @override
  String get noRoomsYet => 'Aucune salle pour le moment';

  @override
  String get noRoomsHint =>
      'Créez ou rejoignez une salle pour commencer à jouer !';

  @override
  String get enterRoomCode => 'Entrez le code de la salle';

  @override
  String members(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString membres',
      one: '1 membre',
    );
    return '$_temp0';
  }

  @override
  String get loginTitle => 'Bon retour';

  @override
  String get loginSubtitle => 'Connectez-vous pour continuer à jouer';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get loginButton => 'Connexion';

  @override
  String get noAccountPrompt => 'Pas encore de compte ?';

  @override
  String get registerLink => 'S\'inscrire';

  @override
  String get registerTitle => 'Créer un compte';

  @override
  String get registerSubtitle => 'Rejoignez SongSpot et commencez à deviner';

  @override
  String get usernameLabel => 'Nom d\'utilisateur';

  @override
  String get confirmPasswordLabel => 'Confirmer le mot de passe';

  @override
  String get registerButton => 'Créer un compte';

  @override
  String get alreadyHaveAccount => 'Déjà un compte ?';

  @override
  String get loginLink => 'Connexion';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsSectionAccount => 'Compte';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsSectionAccessibility => 'Accessibilité';

  @override
  String get settingsSectionLanguage => 'Langue';

  @override
  String get settingsSectionMyData => 'Mes données';

  @override
  String get settingsSectionAbout => 'À propos';

  @override
  String get settingsChangeEmail => 'Changer l\'email';

  @override
  String get settingsChangePassword => 'Changer le mot de passe';

  @override
  String get settingsDailySongNotifications => 'Notifications chanson du jour';

  @override
  String get settingsMessageNotifications => 'Notifications de messages';

  @override
  String get settingsAccessibility => 'Accessibilité';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsExportData => 'Exporter mes données';

  @override
  String get settingsExportDataSubtitle =>
      'Téléchargez une copie de toutes vos données personnelles';

  @override
  String get settingsDeleteAccount => 'Supprimer mon compte';

  @override
  String get settingsDeleteAccountSubtitle =>
      'Supprimez définitivement votre compte et toutes vos données';

  @override
  String get settingsAppVersion => 'Version de l\'application';

  @override
  String get settingsPrivacyPolicy => 'Politique de confidentialité';

  @override
  String get settingsTermsOfService => 'Conditions d\'utilisation';

  @override
  String get accessibilityTitle => 'Accessibilité';

  @override
  String get accessibilityTextSize => 'Taille du texte';

  @override
  String get accessibilityTextSizePreview => 'Aperçu du texte à cette taille';

  @override
  String get accessibilityTextSizeSmall => 'Petit';

  @override
  String get accessibilityTextSizeLarge => 'Grand';

  @override
  String get accessibilityReduceAnimations => 'Réduire les animations';

  @override
  String get accessibilityReduceAnimationsSubtitle =>
      'Minimiser les mouvements dans l\'application';

  @override
  String get accessibilityHighContrast => 'Contraste élevé';

  @override
  String get accessibilityHighContrastSubtitle =>
      'Augmenter le contraste des couleurs pour une meilleure lisibilité';

  @override
  String get accessibilityColorBlindness => 'Mode daltonisme';

  @override
  String get accessibilityColorBlindnessNone => 'Aucun';

  @override
  String get accessibilityColorBlindnessDeuteranopia =>
      'Deutéranopie (rouge-vert)';

  @override
  String get accessibilityColorBlindnessProtanopia => 'Protanopie (rouge)';

  @override
  String get accessibilityColorBlindnessTritanopia => 'Tritanopie (bleu-jaune)';

  @override
  String get accessibilityEnhancedScreenReader => 'Lecteur d\'écran amélioré';

  @override
  String get accessibilityEnhancedScreenReaderSubtitle =>
      'Ajouter des étiquettes plus descriptives pour VoiceOver / TalkBack';

  @override
  String get languageTitle => 'Langue';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get changeEmailTitle => 'Changer l\'email';

  @override
  String get changeEmailCurrentPassword => 'Mot de passe actuel';

  @override
  String get changeEmailNewEmail => 'Nouvelle adresse email';

  @override
  String get changeEmailButton => 'Mettre à jour l\'email';

  @override
  String get changeEmailSuccess => 'Email mis à jour avec succès';

  @override
  String get changePasswordTitle => 'Changer le mot de passe';

  @override
  String get changePasswordCurrent => 'Mot de passe actuel';

  @override
  String get changePasswordNew => 'Nouveau mot de passe';

  @override
  String get changePasswordConfirm => 'Confirmer le nouveau mot de passe';

  @override
  String get changePasswordButton => 'Mettre à jour le mot de passe';

  @override
  String get changePasswordSuccess =>
      'Mot de passe mis à jour. Veuillez vous reconnecter.';

  @override
  String get myDataTitle => 'Mes données';

  @override
  String get myDataExportTitle => 'Exporter vos données';

  @override
  String get myDataExportDescription =>
      'Téléchargez une copie de toutes vos données personnelles, notamment votre profil, l\'historique des parties, les messages et les transactions de pièces.';

  @override
  String get myDataExportButton => 'Exporter mes données';

  @override
  String get myDataDeleteTitle => 'Supprimer votre compte';

  @override
  String get myDataDeleteDescription =>
      'Supprimez définitivement votre compte et toutes les données associées. Cette action est irréversible.';

  @override
  String get myDataDeleteButton => 'Supprimer mon compte';

  @override
  String get myDataDeleteConfirmTitle => 'Supprimer le compte';

  @override
  String get myDataDeleteConfirmMessage =>
      'Cela supprimera définitivement votre compte et toutes vos données. Entrez votre mot de passe pour confirmer.';

  @override
  String get myDataDeleteConfirmButton => 'Supprimer définitivement';

  @override
  String get invalidPassword => 'Mot de passe invalide';

  @override
  String get invalidEmail => 'Adresse email invalide';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get fieldRequired => 'Ce champ est obligatoire';

  @override
  String get undoAction => 'Annuler';

  @override
  String get userFallback => 'Utilisateur';

  @override
  String get dailyStreakTooltip => 'Série quotidienne';

  @override
  String get coinsTooltip => 'Pièces';

  @override
  String get pleaseEnterRoomCode => 'Veuillez entrer un code de salle';

  @override
  String get finishOrUndoCurrentRoomDeletion =>
      'Terminez ou annulez d\'abord la suppression en cours.';

  @override
  String get leftRoomHostTransferred => 'Salle quittée. Hôte transféré.';

  @override
  String get roomRemoved => 'Salle supprimée.';

  @override
  String get roomDeletionCancelled => 'Suppression annulée.';

  @override
  String get deleteLabel => 'Supprimer';

  @override
  String get couldNotDeleteRoom => 'Impossible de supprimer la salle.';

  @override
  String get coinShopTitle => 'Boutique de pièces';

  @override
  String get adNotReadyTryAgain =>
      'La pub n\'est pas prête. Réessayez dans un instant.';

  @override
  String get storeNotAvailableOnDevice =>
      'Boutique indisponible sur cet appareil.';

  @override
  String get productsNotFoundStoreMessage =>
      'Produits introuvables dans la boutique. Vérifiez que vos achats intégrés sont créés et actifs dans App Store Connect / Play Console.';

  @override
  String get getMoreCoinsTitle => 'Obtenir plus de pièces';

  @override
  String get useCoinsToUnlockHint =>
      'Utilisez les pièces pour débloquer des packs et des indices.';

  @override
  String get processingPayment => 'Paiement en cours...';

  @override
  String get pleaseDontCloseApp => 'Ne fermez pas l\'application';

  @override
  String get yourBalance => 'Votre solde';

  @override
  String coinsAmount(num count) {
    return '$count pièces';
  }

  @override
  String get freeBonusCoinsTitle => 'Pièces bonus gratuites';

  @override
  String watchRewardedAdClaimCoins(num coins) {
    return 'Regardez une pub récompensée pour gagner +$coins pièces.';
  }

  @override
  String get checkingDailyLimit => 'Vérification de la limite quotidienne...';

  @override
  String get dailyLimitUnavailable =>
      'Limite quotidienne indisponible pour le moment.';

  @override
  String remainingTodayStatus(num remaining, num cap) {
    return 'Restant aujourd\'hui : $remaining / $cap';
  }

  @override
  String get dailyLimitReached => 'Limite quotidienne atteinte';

  @override
  String get watchAdLabel => 'Regarder la pub';

  @override
  String rewardCoinsAddedToBalance(num coins) {
    return '+$coins pièces ajoutées à votre solde.';
  }

  @override
  String coinsAddedSuccess(num coins) {
    return '+$coins pièces ajoutées !';
  }
}
