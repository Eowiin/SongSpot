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
  String get settingsManageAdConsent => 'Gérer le consentement pub';

  @override
  String get settingsManageAdConsentSubtitle =>
      'Mettre à jour vos choix de confidentialité pub (RGPD)';

  @override
  String get settingsTermsOfService => 'Conditions d\'utilisation';

  @override
  String get settingsSectionShop => 'Boutique';

  @override
  String get settingsCouldNotOpenLink => 'Impossible d\'ouvrir le lien';

  @override
  String get settingsBackLabel => 'Retour';

  @override
  String get settingsNoAdsPassTitle => 'Pass sans pub';

  @override
  String settingsNoAdsActivationPrompt(num coins, num days) {
    return 'Dépenser $coins pièces pour désactiver les pubs pendant $days jours ?';
  }

  @override
  String get settingsActivate => 'Activer';

  @override
  String get settingsNoAdsActivated => 'Pubs désactivées';

  @override
  String settingsNoAdsTitle(num days) {
    return 'Sans pub ($days jours)';
  }

  @override
  String settingsExtendNoAdsTitle(num days) {
    return 'Prolonger Sans pub ($days jours)';
  }

  @override
  String settingsNoAdsActiveUntil(String date) {
    return 'Actif jusqu\'au $date';
  }

  @override
  String settingsNoAdsSpendHint(num coins, num days) {
    return 'Dépensez $coins pièces pour désactiver les pubs pendant $days jours';
  }

  @override
  String get settingsNotActive => 'Non actif';

  @override
  String get adConsentUpdated =>
      'Préférences de consentement pub mises à jour.';

  @override
  String get adConsentNotRequired =>
      'Les options de confidentialité pub ne sont pas requises dans votre région.';

  @override
  String get adConsentError =>
      'Impossible d\'ouvrir les options de confidentialité pub pour le moment.';

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
  String get packListTitle => 'Packs musicaux';

  @override
  String get packBrowseTitle => 'Parcourir les packs';

  @override
  String get packFilterAll => 'Tous';

  @override
  String get packNeedMoreCoins => 'Besoin de plus de pièces ?';

  @override
  String get packGetCoins => 'Obtenir des pièces';

  @override
  String get packPriceFree => 'Gratuit';

  @override
  String packCoinsPrice(num coins) {
    return '$coins pièces';
  }

  @override
  String packProgressDay(num day, num totalDays) {
    return 'Jour $day sur $totalDays';
  }

  @override
  String get packStateInProgress => 'En cours';

  @override
  String get packStateFinishedInRoom => 'Terminé dans cette salle';

  @override
  String get packStateReadyNow => 'Prêt maintenant';

  @override
  String get packStateAfterActivePack => 'Indisponible maintenant';

  @override
  String get packTagInProgress => 'En cours';

  @override
  String get packTagFinished => 'Terminé';

  @override
  String get packTagReadyNow => 'Prêt';

  @override
  String get packTagAfterActivePack => 'Indisponible';

  @override
  String get packActionUnlock => 'Débloquer';

  @override
  String get packActionBuy => 'Acheter';

  @override
  String get packActionInProgress => 'En cours';

  @override
  String get packActionFinished => 'Terminé';

  @override
  String get packActionActivate => 'Activer';

  @override
  String get packActionLater => 'Plus tard';

  @override
  String get packActivatedSuccessfully => 'Pack activé avec succès';

  @override
  String get packUnlockedActivateWhenReady =>
      'Pack débloqué. Activez-le quand vous voulez.';

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

  @override
  String get gamePlayingSnippet => '🔊 Lecture...';

  @override
  String get gamePlaySnippet => 'Écouter l\'extrait';

  @override
  String gameSnippetLabel(num number) {
    return 'Extrait $number';
  }

  @override
  String gamePointsLabel(num points) {
    return '$points points';
  }

  @override
  String get gameMakeYourGuess => 'Faites votre proposition';

  @override
  String get gameSongTitleHint => 'Commencez à taper le titre...';

  @override
  String get gameSongTitleLabel => 'Titre de la chanson';

  @override
  String get gameSkip => 'Passer';

  @override
  String get gameSubmitGuess => 'Valider la proposition';

  @override
  String gameGuessesMade(num count) {
    return 'Propositions faites : $count';
  }

  @override
  String get gameRetryUnlocked =>
      'Seconde chance débloquée. Envoyez une nouvelle proposition.';

  @override
  String get gameWatchAdForRetry => 'Regarder une pub pour rejouer';

  @override
  String gameSpendCoinsForFinalChance(num coins) {
    return 'Dépenser $coins pièces pour une dernière chance';
  }

  @override
  String get gameRetryWatchAdSubtitle =>
      'Vous avez atteint le dernier extrait. Regardez une pub récompensée pour débloquer une seconde chance.';

  @override
  String get gameRetryUseCoinsSubtitle =>
      'Utilisez des pièces pour débloquer une dernière proposition avant les résultats.';

  @override
  String get gameUseRewardForSecondChance =>
      'Utiliser la récompense pour une seconde chance';

  @override
  String get gameExtraChanceTitle => 'Chance supplémentaire';

  @override
  String get gameSkipExtraChanceShowResults =>
      'Passer la chance supplémentaire et afficher les résultats';

  @override
  String get gameHintsTitle => 'Indices';

  @override
  String get gameHintGenre => 'Genre';

  @override
  String get gameHintDecade => 'Décennie';

  @override
  String get gameHintArtist => 'Artiste';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonClose => 'Fermer';

  @override
  String get packModeLabel => 'Pack';

  @override
  String get dailyModesTitle => 'Modes du jour';

  @override
  String get dailyModesShortLabel => 'Modes';

  @override
  String get dailyModesIntro =>
      'Débloquez des pistes supplémentaires pour ce salon sans remplacer Daily Mix.';

  @override
  String get dailyModesRoomIntro =>
      'Mix est toujours gratuit. Contribuez avec votre salon pour débloquer des pistes quotidiennes supplémentaires.';

  @override
  String get dailyModesScrollHint => 'Faites défiler pour voir tous les modes';

  @override
  String get dailyModeMixLabel => 'Daily Mix';

  @override
  String get dailyModeGenreLabel => 'Mode Genre';

  @override
  String get dailyModeDecadeLabel => 'Mode Décennie';

  @override
  String get dailyModeHardcoreLabel => 'Hardcore';

  @override
  String get dailyModeMixSubtitle =>
      'Chanson entièrement aléatoire pour tout le monde aujourd\'hui';

  @override
  String get dailyModeGenreSubtitle =>
      'Genre fixe pour tout le monde aujourd\'hui';

  @override
  String get dailyModeDecadeSubtitle =>
      'Décennie fixe pour tout le monde aujourd\'hui';

  @override
  String get dailyModeHardcoreSubtitle =>
      'Même chanson du jour, mais sans indices ni retries';

  @override
  String dailyModeLaneSubtitle(String name) {
    return 'Piste du jour : $name';
  }

  @override
  String get dailyModeFree => 'Gratuit';

  @override
  String dailyModeCoinsCost(num coins) {
    return '$coins pièces';
  }

  @override
  String get dailyModeUnlockedUntilReset =>
      'Débloqué pour ce salon jusqu\'à la prochaine réinitialisation';

  @override
  String dailyModeContributionProgress(
    num progress,
    num total,
    num contributors,
  ) {
    return '$progress/$total pièces • $contributors contributeurs';
  }

  @override
  String get dailyModePlay => 'Jouer';

  @override
  String get dailyModePreview => 'Aperçu';

  @override
  String get dailyModeUnlocked => 'Débloqué';

  @override
  String get dailyModeContribute => 'Contribuer';

  @override
  String get dailyModeFunded => 'Financé';

  @override
  String dailyModeContributeTitle(String mode) {
    return 'Contribuer à $mode';
  }

  @override
  String dailyModeCoinsRemainingYouHave(num remaining, num coins) {
    return '$remaining pièces restantes. Vous avez actuellement $coins pièces.';
  }

  @override
  String get dailyModeCoinsToContribute => 'Pièces à contribuer';

  @override
  String dailyModeContributionQuickAmount(num amount) {
    return '+$amount';
  }

  @override
  String get dailyModeContributionFill => 'Compléter';

  @override
  String get dailyModeContributionRemainingLabel => 'Reste';

  @override
  String get dailyModeContributionBalanceLabel => 'Votre solde';

  @override
  String dailyModeContributionLeft(num remaining) {
    return '$remaining restantes';
  }

  @override
  String get dailyModeContributionSent => 'Contribution envoyée';

  @override
  String dailyModeUnlockedForRoom(String mode) {
    return '$mode débloqué pour ce salon';
  }

  @override
  String get dailyModeHardcoreRulesTitle => 'Règles Hardcore';

  @override
  String get dailyModeHardcoreRulesBody =>
      'Cette piste désactive les indices et les retries. Une seule tentative.';

  @override
  String get gameSelectSongFromResults =>
      'Veuillez sélectionner une chanson dans les résultats de recherche';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatNoMessagesYet => 'Aucun message pour le moment';

  @override
  String get chatStartConversation => 'Lancez la conversation !';

  @override
  String get chatYou => 'Vous';

  @override
  String get chatTypeMessageHint => 'Écrivez un message...';

  @override
  String get packSearchSongTitleOrArtist => 'Rechercher un titre ou un artiste';

  @override
  String get packSkipInstrument => 'Passer l\'instrument';

  @override
  String get packPlayStems => 'Lire les pistes';

  @override
  String packStageLabel(num number) {
    return 'Étape $number';
  }

  @override
  String packPointsSoFar(num points) {
    return '$points points pour l\'instant';
  }

  @override
  String get packPreparingChallenge => 'Préparation de votre défi...';

  @override
  String get packPreparingChallengeSubtitle => 'Cela peut prendre un instant';

  @override
  String get packStageDrums => 'Batterie';

  @override
  String get packStageBass => 'Basse';

  @override
  String get packStageOther => 'Autres';

  @override
  String get packStageVocals => 'Voix';

  @override
  String get packStemsGeneratingTryAgain =>
      'Les pistes sont en cours de génération. Réessayez dans un instant.';

  @override
  String get packNoStemsAvailableForStage =>
      'Aucune piste disponible pour cette étape';

  @override
  String packFailedToPlayStems(String error) {
    return 'Impossible de lire les pistes : $error';
  }

  @override
  String get packCompleted => 'Pack terminé !';

  @override
  String get packFailed => 'Pack échoué';

  @override
  String packTotalPoints(num points) {
    return 'Points totaux : $points';
  }

  @override
  String get packResultsTitle => 'Résultats du jour';

  @override
  String get packNoOtherPlayersCompleted =>
      'Aucun autre joueur n\'a encore terminé ce pack';

  @override
  String packStageCompletedAt(num stage, String time) {
    return 'Étape $stage - $time';
  }

  @override
  String get dailyResultNoOtherPlayersCompleted =>
      'Aucun autre joueur n\'a encore trouvé la chanson';

  @override
  String dailyResultSnippetCompletedAt(num snippet, String time) {
    return 'Extrait $snippet - $time';
  }

  @override
  String dailyResultNotGuessedAt(String time) {
    return 'Non trouvée - $time';
  }

  @override
  String dailyResultPointsSnippet(num points, num snippet) {
    return '+$points points (Extrait $snippet)';
  }

  @override
  String get backendRoomLimitReached =>
      'Limite de salles atteinte. Supprimez ou quittez une salle avant d\'en créer une autre.';

  @override
  String backendRoomLimitReachedWithLimit(num maxRooms) {
    return 'Limite de salles atteinte ($maxRooms). Supprimez ou quittez une salle avant d\'en créer une autre.';
  }

  @override
  String get backendDailyRoomCreationLimitReached =>
      'Limite quotidienne de création de salles atteinte. Réessayez demain.';

  @override
  String backendDailyRoomCreationLimitReachedWithLimit(num dailyLimit) {
    return 'Limite quotidienne de création de salles atteinte ($dailyLimit). Réessayez demain.';
  }

  @override
  String get backendAlreadyInRoom => 'Vous êtes déjà dans cette salle.';

  @override
  String get backendNotInRoom => 'Vous n\'êtes pas dans cette salle.';

  @override
  String get backendOnlyHostCanRenameRoom =>
      'Seul l\'hôte peut renommer la salle.';

  @override
  String get backendMustBeInRoomToPlayGame =>
      'Vous devez être dans une salle pour jouer.';

  @override
  String get backendRoomNotFound => 'Salle introuvable.';

  @override
  String get backendInsufficientCoins => 'Pièces insuffisantes.';

  @override
  String backendInsufficientCoinsWithCost(num requiredCoins) {
    return 'Pièces insuffisantes. Il vous faut $requiredCoins pièces.';
  }

  @override
  String get backendNoRetriesRemaining =>
      'Plus aucune nouvelle tentative disponible.';

  @override
  String get backendRetryAfterLastSnippetOnly =>
      'La nouvelle tentative est disponible uniquement après le dernier extrait.';

  @override
  String get backendRetryAlreadyActive => 'La seconde chance est déjà active.';

  @override
  String get backendRetryNotPendingUnlock =>
      'La seconde chance n\'est pas disponible pour le moment.';

  @override
  String backendInvalidRetryAction(String expectedAction) {
    return 'Action de seconde chance invalide. Attendu : $expectedAction.';
  }

  @override
  String get backendInvalidRetryActionUnknown =>
      'Action de seconde chance invalide.';

  @override
  String get backendModeRuleRestricted =>
      'Cette action n\'est pas autorisee dans le mode de jeu actuel.';

  @override
  String get backendModeRuleRestrictedHardcoreRetryDisabled =>
      'Le mode hardcore n\'autorise pas les nouvelles tentatives.';

  @override
  String get backendModeRuleRestrictedHardcoreHintsDisabled =>
      'Le mode hardcore n\'autorise pas les indices.';

  @override
  String get backendGameAlreadyCompleted => 'Partie déjà terminée.';

  @override
  String get backendNoActiveGameSession => 'Aucune partie active.';

  @override
  String get backendNoSongAvailableToday =>
      'Aucune chanson disponible aujourd\'hui.';

  @override
  String get backendPackNotOwnedByRoom =>
      'Ce pack n\'est pas possédé par la salle.';

  @override
  String get backendPackHasNoTracks => 'Ce pack ne contient aucune piste.';

  @override
  String get backendNoActivePackSession => 'Aucune session de pack active.';

  @override
  String get backendPackAlreadyCompleted => 'Pack déjà terminé.';

  @override
  String get backendTrackNotFound => 'Piste introuvable.';

  @override
  String get backendAlreadyGuessedForStage =>
      'Vous avez déjà proposé une réponse pour cette étape.';

  @override
  String get backendRoomIdRequired => 'Salle requise.';

  @override
  String get backendInvalidPassword => 'Mot de passe invalide.';

  @override
  String get backendInvalidCurrentPassword => 'Mot de passe actuel invalide.';

  @override
  String get backendInvalidDateFormat =>
      'Format de date invalide. Utilisez AAAA-MM-JJ.';

  @override
  String get backendDateNotInHistory =>
      'Cette date n\'est pas encore dans l\'historique.';

  @override
  String get backendNoSongFoundForDate =>
      'Aucune chanson trouvée pour cette date.';

  @override
  String get backendNoPackTrackForDate =>
      'Aucune piste de pack trouvée pour cette date.';

  @override
  String get backendInvalidCredentials => 'Email ou mot de passe invalide.';

  @override
  String get backendRefreshTokenRequired =>
      'Le jeton de rafraîchissement est requis.';

  @override
  String get backendInvalidOrExpiredRefreshToken =>
      'Le jeton de rafraîchissement est invalide ou expiré.';

  @override
  String get backendInvalidToken => 'Jeton invalide.';

  @override
  String get backendMissingRequiredFields => 'Champs obligatoires manquants.';

  @override
  String get backendInvalidStore => 'Store invalide.';

  @override
  String get backendPurchaseProcessing =>
      'L\'achat est en cours de traitement.';

  @override
  String backendUnknownOrInactiveProduct(String productId) {
    return 'Produit inconnu ou inactif : $productId.';
  }

  @override
  String get backendUnknownOrInactiveProductUnknown =>
      'Produit inconnu ou inactif.';

  @override
  String get backendReceiptVerificationFailed =>
      'La vérification du reçu a échoué.';

  @override
  String get backendNetworkError => 'Erreur réseau';
}
