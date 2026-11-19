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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('fr')];

  /// No description provided for @ok.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @later.
  ///
  /// In fr, this message translates to:
  /// **'Plus tard'**
  String get later;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @choose.
  ///
  /// In fr, this message translates to:
  /// **'Choisir'**
  String get choose;

  /// No description provided for @browse.
  ///
  /// In fr, this message translates to:
  /// **'Parcourir'**
  String get browse;

  /// No description provided for @retry.
  ///
  /// In fr, this message translates to:
  /// **'Réessayer'**
  String get retry;

  /// No description provided for @add.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter'**
  String get add;

  /// No description provided for @website.
  ///
  /// In fr, this message translates to:
  /// **'site web'**
  String get website;

  /// No description provided for @dateTimePattern.
  ///
  /// In fr, this message translates to:
  /// **'dd/MM/yyyy HH:mm'**
  String get dateTimePattern;

  /// No description provided for @decimalSeparator.
  ///
  /// In fr, this message translates to:
  /// **','**
  String get decimalSeparator;

  /// No description provided for @sizeBytes.
  ///
  /// In fr, this message translates to:
  /// **'{n} o'**
  String sizeBytes(String n);

  /// No description provided for @sizeKib.
  ///
  /// In fr, this message translates to:
  /// **'{n} Kio'**
  String sizeKib(String n);

  /// No description provided for @sizeMib.
  ///
  /// In fr, this message translates to:
  /// **'{n} Mio'**
  String sizeMib(String n);

  /// No description provided for @serverUnreachable.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable.'**
  String get serverUnreachable;

  /// No description provided for @language.
  ///
  /// In fr, this message translates to:
  /// **'Langue'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In fr, this message translates to:
  /// **'Langue du système'**
  String get languageSystem;

  /// No description provided for @trayOpen.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir RomSync'**
  String get trayOpen;

  /// No description provided for @traySyncNow.
  ///
  /// In fr, this message translates to:
  /// **'Synchroniser maintenant'**
  String get traySyncNow;

  /// No description provided for @trayQuit.
  ///
  /// In fr, this message translates to:
  /// **'Quitter RomSync'**
  String get trayQuit;

  /// No description provided for @pairTitle.
  ///
  /// In fr, this message translates to:
  /// **'Appairer cet appareil'**
  String get pairTitle;

  /// No description provided for @pairIntro.
  ///
  /// In fr, this message translates to:
  /// **'Sur le site RomSync : Appareils → Ajouter un appareil, puis saisis le code ici.'**
  String get pairIntro;

  /// No description provided for @pairServer.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du serveur'**
  String get pairServer;

  /// No description provided for @pairServerRequired.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du serveur requise'**
  String get pairServerRequired;

  /// No description provided for @pairServerInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Adresse invalide (ex. http://nas:8080)'**
  String get pairServerInvalid;

  /// No description provided for @pairCode.
  ///
  /// In fr, this message translates to:
  /// **'Code d’appairage'**
  String get pairCode;

  /// No description provided for @pairCodeInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Code de 8 caractères (ex. K7QM-4XPA)'**
  String get pairCodeInvalid;

  /// No description provided for @pairName.
  ///
  /// In fr, this message translates to:
  /// **'Nom de l’appareil'**
  String get pairName;

  /// No description provided for @pairNameRequired.
  ///
  /// In fr, this message translates to:
  /// **'Nom requis'**
  String get pairNameRequired;

  /// No description provided for @pairSubmit.
  ///
  /// In fr, this message translates to:
  /// **'Appairer'**
  String get pairSubmit;

  /// No description provided for @pairNoKeyringTitle.
  ///
  /// In fr, this message translates to:
  /// **'Aucun trousseau disponible'**
  String get pairNoKeyringTitle;

  /// No description provided for @pairNoKeyringBody.
  ///
  /// In fr, this message translates to:
  /// **'RomSync range le jeton de l’appareil dans le trousseau du système (Secret Service : GNOME Keyring, KWallet, KeePassXC…), mais aucun ne répond dans cette session.\n\nTu peux démarrer un trousseau puis réessayer, ou stocker le jeton dans un fichier.'**
  String get pairNoKeyringBody;

  /// No description provided for @tokenFileWarning.
  ///
  /// In fr, this message translates to:
  /// **'Le jeton de cet appareil est stocké en clair dans un fichier (permissions 0600). Toute personne ou application ayant accès à ton compte peut le lire ; en cas de doute, révoque l’appareil depuis le site.'**
  String get tokenFileWarning;

  /// No description provided for @pairUseFile.
  ///
  /// In fr, this message translates to:
  /// **'Stocker le jeton dans un fichier'**
  String get pairUseFile;

  /// No description provided for @pairCodeExpired.
  ///
  /// In fr, this message translates to:
  /// **'Ce code a expiré ou a déjà été utilisé : génère-en un nouveau sur le site.'**
  String get pairCodeExpired;

  /// No description provided for @pairCodeUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Code inconnu : vérifie-le, ou génère-en un nouveau sur le site.'**
  String get pairCodeUnknown;

  /// No description provided for @rateLimited.
  ///
  /// In fr, this message translates to:
  /// **'Trop de tentatives : réessaie dans une minute.'**
  String get rateLimited;

  /// No description provided for @pairUnreachable.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : vérifie l’adresse et ta connexion (Tailscale ?).'**
  String get pairUnreachable;

  /// No description provided for @homeRescan.
  ///
  /// In fr, this message translates to:
  /// **'Rescanner et synchroniser'**
  String get homeRescan;

  /// No description provided for @settings.
  ///
  /// In fr, this message translates to:
  /// **'Réglages'**
  String get settings;

  /// No description provided for @homeUnauthorized.
  ///
  /// In fr, this message translates to:
  /// **'Cet appareil a été révoqué ou son jeton n’est plus valide : appaire-le à nouveau.'**
  String get homeUnauthorized;

  /// No description provided for @homePairAgain.
  ///
  /// In fr, this message translates to:
  /// **'Appairer à nouveau'**
  String get homePairAgain;

  /// No description provided for @homeOffline.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : les parties se lancent avec les saves locales.'**
  String get homeOffline;

  /// No description provided for @homeOfflineQueued.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : les parties se lancent avec les saves locales, {count, plural, =1{1 envoi en attente} other{{count} envois en attente}}.'**
  String homeOfflineQueued(int count);

  /// No description provided for @homeRunning.
  ///
  /// In fr, this message translates to:
  /// **'Partie en cours : {game}. Chaque sauvegarde est envoyée automatiquement.'**
  String homeRunning(String game);

  /// No description provided for @homeDivergence.
  ///
  /// In fr, this message translates to:
  /// **'Choix à faire pour {game} : deux appareils ont joué sans se synchroniser. Rien n’a été envoyé.'**
  String homeDivergence(String game);

  /// No description provided for @homeAddFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ajoute un dossier de ROMs dans les réglages.'**
  String get homeAddFolder;

  /// No description provided for @homeScanIssues.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 fichier non lu} other{{count} fichiers non lus}}'**
  String homeScanIssues(int count);

  /// No description provided for @homeActivity.
  ///
  /// In fr, this message translates to:
  /// **'Activité récente'**
  String get homeActivity;

  /// No description provided for @divergenceLocalSent.
  ///
  /// In fr, this message translates to:
  /// **'Save locale envoyée : c’est la save active.'**
  String get divergenceLocalSent;

  /// No description provided for @divergenceServerTaken.
  ///
  /// In fr, this message translates to:
  /// **'Save du serveur récupérée ; ta save locale est dans l’historique.'**
  String get divergenceServerTaken;

  /// No description provided for @divergenceServerTakenBackup.
  ///
  /// In fr, this message translates to:
  /// **'Save du serveur récupérée ; ta save locale est dans l’historique et dans {path}.'**
  String divergenceServerTakenBackup(String path);

  /// No description provided for @launchFailed.
  ///
  /// In fr, this message translates to:
  /// **'Lancement impossible'**
  String get launchFailed;

  /// No description provided for @staleTitle.
  ///
  /// In fr, this message translates to:
  /// **'Une save {emulator} existe déjà'**
  String staleTitle(String emulator);

  /// No description provided for @staleBody.
  ///
  /// In fr, this message translates to:
  /// **'RomSync ne l’a jamais synchronisée pour ce jeu : c’est probablement une ancienne partie.\n\nMise de côté (recommandé), elle est copiée dans le dossier .backup voisin, et la save du serveur sera téléchargée au prochain lancement.\nGardée, elle sera envoyée au serveur, qui gardera la plus récente des deux.'**
  String get staleBody;

  /// No description provided for @staleKeep.
  ///
  /// In fr, this message translates to:
  /// **'La garder'**
  String get staleKeep;

  /// No description provided for @staleSetAside.
  ///
  /// In fr, this message translates to:
  /// **'La mettre de côté'**
  String get staleSetAside;

  /// No description provided for @gameSharedNeedsChoice.
  ///
  /// In fr, this message translates to:
  /// **'{count} ROMs partagent l’identifiant {id} : choisis pour celle-ci.'**
  String gameSharedNeedsChoice(int count, String id);

  /// No description provided for @gameShared.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Save partagée avec 1 autre ROM} other{Save partagée avec {count} autres ROMs}}'**
  String gameShared(int count);

  /// No description provided for @gameSeparate.
  ///
  /// In fr, this message translates to:
  /// **'Save séparée'**
  String get gameSeparate;

  /// No description provided for @gameModify.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get gameModify;

  /// No description provided for @gameEmulatorTooltip.
  ///
  /// In fr, this message translates to:
  /// **'Émulateur de ce jeu'**
  String get gameEmulatorTooltip;

  /// No description provided for @emulatorDefault.
  ///
  /// In fr, this message translates to:
  /// **'{name} (par défaut)'**
  String emulatorDefault(String name);

  /// No description provided for @emulatorNoArchives.
  ///
  /// In fr, this message translates to:
  /// **'{name} — pas pour les archives'**
  String emulatorNoArchives(String name);

  /// No description provided for @history.
  ///
  /// In fr, this message translates to:
  /// **'Historique'**
  String get history;

  /// No description provided for @play.
  ///
  /// In fr, this message translates to:
  /// **'Jouer'**
  String get play;

  /// No description provided for @launchDownloaded.
  ///
  /// In fr, this message translates to:
  /// **'Save du serveur téléchargée.'**
  String get launchDownloaded;

  /// No description provided for @launchDownloadedBackup.
  ///
  /// In fr, this message translates to:
  /// **'Save du serveur téléchargée ; l’ancienne copie locale est dans {path}.'**
  String launchDownloadedBackup(String path);

  /// No description provided for @notPaired.
  ///
  /// In fr, this message translates to:
  /// **'Appareil non appairé.'**
  String get notPaired;

  /// No description provided for @closeGameFirst.
  ///
  /// In fr, this message translates to:
  /// **'Ferme d’abord le jeu en cours : RomSync téléchargera ensuite la save du serveur.'**
  String get closeGameFirst;

  /// No description provided for @gameAlreadyRunning.
  ///
  /// In fr, this message translates to:
  /// **'Une partie est déjà en cours : {game}.'**
  String gameAlreadyRunning(String game);

  /// No description provided for @noticeNewSaveTitle.
  ///
  /// In fr, this message translates to:
  /// **'Nouvelle save : {title}'**
  String noticeNewSaveTitle(String title);

  /// No description provided for @noticeChoiceTitle.
  ///
  /// In fr, this message translates to:
  /// **'Choix à faire pour {game}'**
  String noticeChoiceTitle(String game);

  /// No description provided for @noticeChoiceBody.
  ///
  /// In fr, this message translates to:
  /// **'Deux appareils ont joué sans se synchroniser : rien n’a été envoyé. Ouvre RomSync pour choisir la save à garder.'**
  String get noticeChoiceBody;

  /// No description provided for @updateWaitGame.
  ///
  /// In fr, this message translates to:
  /// **'Partie en cours ({game}) : la mise à jour s’installera à la fin de la partie.'**
  String updateWaitGame(String game);

  /// No description provided for @updateWaitQueue.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 envoi en attente} other{{count} envois en attente}} : la mise à jour s’installera dès qu’ils seront partis.'**
  String updateWaitQueue(int count);

  /// No description provided for @updateWaitQueueHeld.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 envoi en attente} other{{count} envois en attente}}, dont {held} en attente de ton choix (divergence) : la mise à jour s’installera dès qu’ils seront partis.'**
  String updateWaitQueueHeld(int count, int held);

  /// No description provided for @statusUpToDate.
  ///
  /// In fr, this message translates to:
  /// **'À jour'**
  String get statusUpToDate;

  /// No description provided for @statusToUpload.
  ///
  /// In fr, this message translates to:
  /// **'À envoyer'**
  String get statusToUpload;

  /// No description provided for @statusToDownload.
  ///
  /// In fr, this message translates to:
  /// **'À télécharger'**
  String get statusToDownload;

  /// No description provided for @statusOffline.
  ///
  /// In fr, this message translates to:
  /// **'Hors ligne'**
  String get statusOffline;

  /// No description provided for @statusNeedsChoice.
  ///
  /// In fr, this message translates to:
  /// **'Choix requis'**
  String get statusNeedsChoice;

  /// No description provided for @statusDiverged.
  ///
  /// In fr, this message translates to:
  /// **'Choix à faire'**
  String get statusDiverged;

  /// No description provided for @statusUnavailable.
  ///
  /// In fr, this message translates to:
  /// **'Indisponible'**
  String get statusUnavailable;

  /// No description provided for @statusNoSave.
  ///
  /// In fr, this message translates to:
  /// **'Pas de save'**
  String get statusNoSave;

  /// No description provided for @conflictResolved.
  ///
  /// In fr, this message translates to:
  /// **'Conflit résolu automatiquement'**
  String get conflictResolved;

  /// No description provided for @conflictResolvedTooltip.
  ///
  /// In fr, this message translates to:
  /// **'La dernière save envoyée ne partait pas de la version active : les deux sont dans l’historique du site.'**
  String get conflictResolvedTooltip;

  /// No description provided for @copyCommand.
  ///
  /// In fr, this message translates to:
  /// **'Copier la commande'**
  String get copyCommand;

  /// No description provided for @commandCopied.
  ///
  /// In fr, this message translates to:
  /// **'Commande copiée'**
  String get commandCopied;

  /// No description provided for @settingsServer.
  ///
  /// In fr, this message translates to:
  /// **'Serveur'**
  String get settingsServer;

  /// No description provided for @settingsDevice.
  ///
  /// In fr, this message translates to:
  /// **'Appareil « {name} » · {storage}'**
  String settingsDevice(String name, String storage);

  /// No description provided for @tokenInKeyring.
  ///
  /// In fr, this message translates to:
  /// **'jeton dans le trousseau du système'**
  String get tokenInKeyring;

  /// No description provided for @tokenInFile.
  ///
  /// In fr, this message translates to:
  /// **'jeton dans un fichier (0600)'**
  String get tokenInFile;

  /// No description provided for @unpair.
  ///
  /// In fr, this message translates to:
  /// **'Désappairer'**
  String get unpair;

  /// No description provided for @romFolders.
  ///
  /// In fr, this message translates to:
  /// **'Dossiers de ROMs'**
  String get romFolders;

  /// No description provided for @romFoldersHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les .nds sont lus, y compris dans les .zip et les .7z (programme 7z, 7zz ou 7za).'**
  String get romFoldersHelp;

  /// No description provided for @addFolder.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un dossier'**
  String get addFolder;

  /// No description provided for @emulators.
  ///
  /// In fr, this message translates to:
  /// **'Émulateurs'**
  String get emulators;

  /// No description provided for @systemNds.
  ///
  /// In fr, this message translates to:
  /// **'Nintendo DS'**
  String get systemNds;

  /// No description provided for @systemGba.
  ///
  /// In fr, this message translates to:
  /// **'Game Boy Advance'**
  String get systemGba;

  /// No description provided for @systemGb.
  ///
  /// In fr, this message translates to:
  /// **'Game Boy et Game Boy Color'**
  String get systemGb;

  /// No description provided for @defaultEmulatorOf.
  ///
  /// In fr, this message translates to:
  /// **'Émulateur par défaut ({system})'**
  String defaultEmulatorOf(String system);

  /// No description provided for @defaultEmulator.
  ///
  /// In fr, this message translates to:
  /// **'Émulateur par défaut'**
  String get defaultEmulator;

  /// No description provided for @defaultEmulatorHelp.
  ///
  /// In fr, this message translates to:
  /// **'Chaque jeu peut avoir le sien, depuis la liste des jeux.'**
  String get defaultEmulatorHelp;

  /// No description provided for @tray.
  ///
  /// In fr, this message translates to:
  /// **'Barre système'**
  String get tray;

  /// No description provided for @keepInTray.
  ///
  /// In fr, this message translates to:
  /// **'Garder RomSync dans la barre système à la fermeture'**
  String get keepInTray;

  /// No description provided for @keepInTrayHelp.
  ///
  /// In fr, this message translates to:
  /// **'Les saves des jeux lancés sans passer par RomSync sont alors envoyées automatiquement. Les saves plus récentes du serveur sont signalées par une notification, et téléchargées au prochain lancement depuis RomSync.'**
  String get keepInTrayHelp;

  /// No description provided for @backups.
  ///
  /// In fr, this message translates to:
  /// **'Copies de sécurité'**
  String get backups;

  /// No description provided for @backupCount.
  ///
  /// In fr, this message translates to:
  /// **'Copies .backup gardées par save'**
  String get backupCount;

  /// No description provided for @backupHelp.
  ///
  /// In fr, this message translates to:
  /// **'Copie de la save locale remplacée par un téléchargement, dans un dossier .backup à côté.'**
  String get backupHelp;

  /// No description provided for @updates.
  ///
  /// In fr, this message translates to:
  /// **'Mises à jour'**
  String get updates;

  /// No description provided for @autoUpdate.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher les mises à jour automatiquement'**
  String get autoUpdate;

  /// No description provided for @autoUpdateHelp.
  ///
  /// In fr, this message translates to:
  /// **'Au démarrage puis toutes les 24 heures, auprès de ton serveur RomSync. Rien n’est installé sans ton accord.'**
  String get autoUpdateHelp;

  /// No description provided for @lastCheck.
  ///
  /// In fr, this message translates to:
  /// **'Dernière vérification : {date}'**
  String lastCheck(String date);

  /// No description provided for @seeUpdate.
  ///
  /// In fr, this message translates to:
  /// **'Voir la mise à jour'**
  String get seeUpdate;

  /// No description provided for @checkUpdate.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher une mise à jour'**
  String get checkUpdate;

  /// No description provided for @emuDefault.
  ///
  /// In fr, this message translates to:
  /// **'par défaut'**
  String get emuDefault;

  /// No description provided for @emuInUse.
  ///
  /// In fr, this message translates to:
  /// **'utilisé par certains jeux'**
  String get emuInUse;

  /// No description provided for @emuFormatToCheck.
  ///
  /// In fr, this message translates to:
  /// **'format de save à vérifier'**
  String get emuFormatToCheck;

  /// No description provided for @emuToConfigure.
  ///
  /// In fr, this message translates to:
  /// **'à configurer'**
  String get emuToConfigure;

  /// No description provided for @emuExecutable.
  ///
  /// In fr, this message translates to:
  /// **'Exécutable'**
  String get emuExecutable;

  /// No description provided for @emuAppMac.
  ///
  /// In fr, this message translates to:
  /// **'Application (.app)'**
  String get emuAppMac;

  /// No description provided for @emuExeWindows.
  ///
  /// In fr, this message translates to:
  /// **'Exécutable (.exe)'**
  String get emuExeWindows;

  /// No description provided for @emuExeLinux.
  ///
  /// In fr, this message translates to:
  /// **'Exécutable (nom dans le PATH ou chemin complet)'**
  String get emuExeLinux;

  /// No description provided for @emuArgs.
  ///
  /// In fr, this message translates to:
  /// **'Arguments supplémentaires'**
  String get emuArgs;

  /// No description provided for @emuSaveDir.
  ///
  /// In fr, this message translates to:
  /// **'Dossier des saves (vide : détecté)'**
  String get emuSaveDir;

  /// No description provided for @emuDetected.
  ///
  /// In fr, this message translates to:
  /// **'Détecté : {where} (source : {source})'**
  String emuDetected(String where, String source);

  /// No description provided for @emuDetectedRetroarch.
  ///
  /// In fr, this message translates to:
  /// **'selon la configuration de RetroArch'**
  String get emuDetectedRetroarch;

  /// No description provided for @emuDetectedUnknown.
  ///
  /// In fr, this message translates to:
  /// **'inconnu'**
  String get emuDetectedUnknown;

  /// No description provided for @emuDetectedNextToRom.
  ///
  /// In fr, this message translates to:
  /// **'à côté de chaque ROM'**
  String get emuDetectedNextToRom;

  /// No description provided for @chooseFolder.
  ///
  /// In fr, this message translates to:
  /// **'Choisir un dossier'**
  String get chooseFolder;

  /// No description provided for @historyTitle.
  ///
  /// In fr, this message translates to:
  /// **'Historique — {title}'**
  String historyTitle(String title);

  /// No description provided for @historyRestoreOnSite.
  ///
  /// In fr, this message translates to:
  /// **'Restaurer sur le site'**
  String get historyRestoreOnSite;

  /// No description provided for @historyNoSave.
  ///
  /// In fr, this message translates to:
  /// **'Ce jeu n’a pas encore de save sur le serveur.'**
  String get historyNoSave;

  /// No description provided for @historyReadOnly.
  ///
  /// In fr, this message translates to:
  /// **'Lecture seule : pour restaurer une ancienne version, ouvre le jeu sur le site. L’appli la téléchargera avant la prochaine partie.'**
  String get historyReadOnly;

  /// No description provided for @versionActive.
  ///
  /// In fr, this message translates to:
  /// **'active'**
  String get versionActive;

  /// No description provided for @versionDivergent.
  ///
  /// In fr, this message translates to:
  /// **'divergente'**
  String get versionDivergent;

  /// No description provided for @versionPinned.
  ///
  /// In fr, this message translates to:
  /// **'épinglée'**
  String get versionPinned;

  /// No description provided for @versionClockFixed.
  ///
  /// In fr, this message translates to:
  /// **'horloge corrigée'**
  String get versionClockFixed;

  /// No description provided for @versionNote.
  ///
  /// In fr, this message translates to:
  /// **'« {note} »'**
  String versionNote(String note);

  /// No description provided for @sizeTrimmed.
  ///
  /// In fr, this message translates to:
  /// **'reçue en {from}, remplissage coupé'**
  String sizeTrimmed(String from);

  /// No description provided for @sizeShrunk.
  ///
  /// In fr, this message translates to:
  /// **'taille du jeu passée de {from} à {to}'**
  String sizeShrunk(String from, String to);

  /// No description provided for @sizeForced.
  ///
  /// In fr, this message translates to:
  /// **'taille forcée (avant : {from})'**
  String sizeForced(String from);

  /// No description provided for @olderVersions.
  ///
  /// In fr, this message translates to:
  /// **'Versions plus anciennes'**
  String get olderVersions;

  /// No description provided for @choiceTitle.
  ///
  /// In fr, this message translates to:
  /// **'Plusieurs ROMs, un même jeu'**
  String get choiceTitle;

  /// No description provided for @choiceSameId.
  ///
  /// In fr, this message translates to:
  /// **'« {rom} » a le même identifiant ({id}) que :'**
  String choiceSameId(String rom, String id);

  /// No description provided for @choiceNotSynced.
  ///
  /// In fr, this message translates to:
  /// **'Tant que tu n’as pas choisi, cette ROM n’est pas synchronisée.'**
  String get choiceNotSynced;

  /// No description provided for @choiceShare.
  ///
  /// In fr, this message translates to:
  /// **'Partager la save'**
  String get choiceShare;

  /// No description provided for @choiceShareHelp.
  ///
  /// In fr, this message translates to:
  /// **'Même progression que les autres ROMs de ce jeu (ROM patchée ou traduite).'**
  String get choiceShareHelp;

  /// No description provided for @choiceSeparate.
  ///
  /// In fr, this message translates to:
  /// **'Séparer'**
  String get choiceSeparate;

  /// No description provided for @choiceSeparateHelp.
  ///
  /// In fr, this message translates to:
  /// **'Sa propre save sur le serveur, sous un identifiant que tu nommes (hack qui change la save).'**
  String get choiceSeparateHelp;

  /// No description provided for @choiceIdName.
  ///
  /// In fr, this message translates to:
  /// **'Nom de l’identifiant'**
  String get choiceIdName;

  /// No description provided for @choiceIdHelp.
  ///
  /// In fr, this message translates to:
  /// **'Lettres, chiffres et tirets, 32 caractères au plus'**
  String get choiceIdHelp;

  /// No description provided for @choiceIdPreview.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant : {id}'**
  String choiceIdPreview(String id);

  /// No description provided for @choiceIdInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Nom invalide : lettres sans accents, chiffres et tirets'**
  String get choiceIdInvalid;

  /// No description provided for @validate.
  ///
  /// In fr, this message translates to:
  /// **'Valider'**
  String get validate;

  /// No description provided for @divTitle.
  ///
  /// In fr, this message translates to:
  /// **'Deux appareils ont joué sans se synchroniser'**
  String get divTitle;

  /// No description provided for @divServer.
  ///
  /// In fr, this message translates to:
  /// **'• Sur le serveur : save du {date}, venant de {from}.'**
  String divServer(String date, String from);

  /// No description provided for @divFromWebsite.
  ///
  /// In fr, this message translates to:
  /// **'l’import sur le site'**
  String get divFromWebsite;

  /// No description provided for @divLocalUnknown.
  ///
  /// In fr, this message translates to:
  /// **'• Sur cet appareil : une autre save, modifiée depuis la dernière synchronisation.'**
  String get divLocalUnknown;

  /// No description provided for @divLocal.
  ///
  /// In fr, this message translates to:
  /// **'• Sur cet appareil : save modifiée le {date}, qui ne part pas de celle du serveur.'**
  String divLocal(String date);

  /// No description provided for @divExplain.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer ma save locale : elle devient la save active et les autres appareils la téléchargeront.\nPrendre celle du serveur : ta save locale est quand même envoyée, comme ancienne version (restaurable sur le site), puis remplacée par celle du serveur ; une copie reste dans le dossier .backup.'**
  String get divExplain;

  /// No description provided for @divCloseEmulator.
  ///
  /// In fr, this message translates to:
  /// **'Ferme d’abord l’émulateur s’il a encore ce jeu ouvert.'**
  String get divCloseEmulator;

  /// No description provided for @divLaterLaunch.
  ///
  /// In fr, this message translates to:
  /// **'Plus tard : rien n’est envoyé ni écrasé, et le jeu ne se lance pas.'**
  String get divLaterLaunch;

  /// No description provided for @divLater.
  ///
  /// In fr, this message translates to:
  /// **'Plus tard : rien n’est envoyé ni écrasé.'**
  String get divLater;

  /// No description provided for @divTakeServer.
  ///
  /// In fr, this message translates to:
  /// **'Prendre celle du serveur'**
  String get divTakeServer;

  /// No description provided for @divSendLocal.
  ///
  /// In fr, this message translates to:
  /// **'Envoyer ma save locale'**
  String get divSendLocal;

  /// No description provided for @updateCurrent.
  ///
  /// In fr, this message translates to:
  /// **'Version actuelle : {version}'**
  String updateCurrent(String version);

  /// No description provided for @updateNoNotes.
  ///
  /// In fr, this message translates to:
  /// **'Pas de notes de version.'**
  String get updateNoNotes;

  /// No description provided for @updateVerifiedInfo.
  ///
  /// In fr, this message translates to:
  /// **'Le téléchargement est vérifié (signature et empreinte) avant d’être proposé à l’installation. RomSync te demandera ton accord avant d’installer et de redémarrer.'**
  String get updateVerifiedInfo;

  /// No description provided for @download.
  ///
  /// In fr, this message translates to:
  /// **'Télécharger'**
  String get download;

  /// No description provided for @installTitle.
  ///
  /// In fr, this message translates to:
  /// **'Installer RomSync {version} ?'**
  String installTitle(String version);

  /// No description provided for @installBody.
  ///
  /// In fr, this message translates to:
  /// **'RomSync va se fermer, installer la nouvelle version, puis redémarrer. Si l’installation échoue, la version actuelle reste en place. Pendant une partie ou avec des envois en attente, l’installation attend qu’ils soient terminés.'**
  String get installBody;

  /// No description provided for @installRestart.
  ///
  /// In fr, this message translates to:
  /// **'Installer et redémarrer'**
  String get installRestart;

  /// No description provided for @updateAvailableDefault.
  ///
  /// In fr, this message translates to:
  /// **'Une nouvelle version est disponible.'**
  String get updateAvailableDefault;

  /// No description provided for @seeNotes.
  ///
  /// In fr, this message translates to:
  /// **'Voir les notes'**
  String get seeNotes;

  /// No description provided for @compatServerTooOld.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur RomSync ({version}) est trop ancien pour cette appli : mets d’abord à jour le serveur (nouvelle image Docker). En attendant, le choix en cas de divergence n’est pas disponible.'**
  String compatServerTooOld(String version);

  /// No description provided for @compatOldVersion.
  ///
  /// In fr, this message translates to:
  /// **'version antérieure à 0.5.0'**
  String get compatOldVersion;

  /// No description provided for @compatClientTooOld.
  ///
  /// In fr, this message translates to:
  /// **'Cette appli ({version}) est trop ancienne pour le serveur, qui demande au moins {min} : mets-la à jour.'**
  String compatClientTooOld(String version, String min);

  /// No description provided for @updDev.
  ///
  /// In fr, this message translates to:
  /// **'Version de développement : pas de mise à jour automatique.'**
  String get updDev;

  /// No description provided for @updNoPlatform.
  ///
  /// In fr, this message translates to:
  /// **'Pas de mise à jour pour ce système.'**
  String get updNoPlatform;

  /// No description provided for @updPairFirst.
  ///
  /// In fr, this message translates to:
  /// **'Appaire d’abord cet appareil.'**
  String get updPairFirst;

  /// No description provided for @updAvailable.
  ///
  /// In fr, this message translates to:
  /// **'RomSync {version} est disponible.'**
  String updAvailable(String version);

  /// No description provided for @updNoticeTitle.
  ///
  /// In fr, this message translates to:
  /// **'RomSync {version} est disponible'**
  String updNoticeTitle(String version);

  /// No description provided for @updNoticeBody.
  ///
  /// In fr, this message translates to:
  /// **'Ouvre RomSync pour lire les notes de version et installer la mise à jour.'**
  String get updNoticeBody;

  /// No description provided for @updNoRelay.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur ne propose pas de mise à jour (relais désactivé, serveur trop ancien ou aucune version publiée).'**
  String get updNoRelay;

  /// No description provided for @updUpToDate.
  ///
  /// In fr, this message translates to:
  /// **'RomSync est à jour ({version}).'**
  String updUpToDate(String version);

  /// No description provided for @updUnreachable.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : vérification reportée.'**
  String get updUnreachable;

  /// No description provided for @updCheckFailed.
  ///
  /// In fr, this message translates to:
  /// **'Vérification impossible : {detail}'**
  String updCheckFailed(String detail);

  /// No description provided for @updDownloading.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement de RomSync {version}…'**
  String updDownloading(String version);

  /// No description provided for @updVerifying.
  ///
  /// In fr, this message translates to:
  /// **'Vérification de la signature…'**
  String get updVerifying;

  /// No description provided for @updNotWritable.
  ///
  /// In fr, this message translates to:
  /// **'Le dossier d’installation ({path}) n’est pas modifiable : installe la nouvelle version à la main, ou déplace RomSync dans un dossier à toi.'**
  String updNotWritable(String path);

  /// No description provided for @updReady.
  ///
  /// In fr, this message translates to:
  /// **'RomSync {version} est prête à être installée.'**
  String updReady(String version);

  /// No description provided for @updUnreachableDownload.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable pendant le téléchargement.'**
  String get updUnreachableDownload;

  /// No description provided for @updDownloadFailed.
  ///
  /// In fr, this message translates to:
  /// **'Téléchargement impossible : {detail}'**
  String updDownloadFailed(String detail);

  /// No description provided for @updInstallFailedWith.
  ///
  /// In fr, this message translates to:
  /// **'{detail} RomSync continue avec la version actuelle.'**
  String updInstallFailedWith(String detail);

  /// No description provided for @updInstallFailed.
  ///
  /// In fr, this message translates to:
  /// **'Installation impossible ({detail}). RomSync continue avec la version actuelle.'**
  String updInstallFailed(String detail);

  /// No description provided for @updInstalling.
  ///
  /// In fr, this message translates to:
  /// **'Installation…'**
  String get updInstalling;

  /// No description provided for @updUpdaterMissing.
  ///
  /// In fr, this message translates to:
  /// **'romsync-updater.exe est introuvable.'**
  String get updUpdaterMissing;

  /// No description provided for @coreSyncNeedsChoice.
  ///
  /// In fr, this message translates to:
  /// **'Deux appareils ont joué sans se synchroniser : choix à faire'**
  String get coreSyncNeedsChoice;

  /// No description provided for @coreSyncIdentical.
  ///
  /// In fr, this message translates to:
  /// **'Save identique à la version active'**
  String get coreSyncIdentical;

  /// No description provided for @coreSyncArchived.
  ///
  /// In fr, this message translates to:
  /// **'Save locale archivée sur le serveur'**
  String get coreSyncArchived;

  /// No description provided for @coreSyncUploaded.
  ///
  /// In fr, this message translates to:
  /// **'Save envoyée'**
  String get coreSyncUploaded;

  /// No description provided for @coreSyncUploadedDivergent.
  ///
  /// In fr, this message translates to:
  /// **'Save envoyée (divergence)'**
  String get coreSyncUploadedDivergent;

  /// No description provided for @coreSyncUploadedNotActive.
  ///
  /// In fr, this message translates to:
  /// **'Save envoyée, mais une version plus récente reste active'**
  String get coreSyncUploadedNotActive;

  /// No description provided for @coreSyncOffline.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : {count, plural, =1{1 envoi en attente} other{{count} envois en attente}}'**
  String coreSyncOffline(int count);

  /// No description provided for @coreSyncUnauthorized.
  ///
  /// In fr, this message translates to:
  /// **'Appareil non autorisé : appaire-le à nouveau.'**
  String get coreSyncUnauthorized;

  /// No description provided for @coreSyncRefused.
  ///
  /// In fr, this message translates to:
  /// **'Envoi refusé ({code}) : {detail}. Copie conservée : {copy}'**
  String coreSyncRefused(String code, String detail, String copy);

  /// No description provided for @coreSyncQueued.
  ///
  /// In fr, this message translates to:
  /// **'Save mise en file d’attente'**
  String get coreSyncQueued;

  /// No description provided for @coreSyncUpToDate.
  ///
  /// In fr, this message translates to:
  /// **'Save à jour'**
  String get coreSyncUpToDate;

  /// No description provided for @coreSyncDownloaded.
  ///
  /// In fr, this message translates to:
  /// **'Save du serveur téléchargée'**
  String get coreSyncDownloaded;

  /// No description provided for @coreSyncOfflineLaunch.
  ///
  /// In fr, this message translates to:
  /// **'Serveur injoignable : la partie se lance avec la save locale, les envois partiront dès que le serveur répondra.'**
  String get coreSyncOfflineLaunch;

  /// No description provided for @coreSyncSharedId.
  ///
  /// In fr, this message translates to:
  /// **'Plusieurs ROMs partagent l’identifiant {gameId} : choisis d’abord de partager ou séparer leur save.'**
  String coreSyncSharedId(String gameId);

  /// No description provided for @coreSyncServerTooOld.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur RomSync ({version}) est trop ancien pour appliquer ce choix : rien n’a été envoyé ni écrasé. Mets d’abord à jour le serveur, puis recommence.'**
  String coreSyncServerTooOld(String version);

  /// No description provided for @coreSyncServerTooOldForConsole.
  ///
  /// In fr, this message translates to:
  /// **'Le serveur RomSync ({version}) ne connaît pas encore cette console : la save attend dans la file. Mets d’abord à jour le serveur.'**
  String coreSyncServerTooOldForConsole(String version);

  /// No description provided for @coreFileProblem.
  ///
  /// In fr, this message translates to:
  /// **'{file} : {reason}'**
  String coreFileProblem(String file, String reason);

  /// No description provided for @coreFileBadFormat.
  ///
  /// In fr, this message translates to:
  /// **'{file} : format inattendu ({detail})'**
  String coreFileBadFormat(String file, String detail);

  /// No description provided for @coreFileChanging.
  ///
  /// In fr, this message translates to:
  /// **'le fichier change pendant la lecture'**
  String get coreFileChanging;

  /// No description provided for @coreFileStillWriting.
  ///
  /// In fr, this message translates to:
  /// **'le fichier est encore en cours d’écriture'**
  String get coreFileStillWriting;

  /// No description provided for @coreFileLocked.
  ///
  /// In fr, this message translates to:
  /// **'fichier verrouillé par un autre programme ({detail})'**
  String coreFileLocked(String detail);

  /// No description provided for @coreFileUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'lecture impossible'**
  String get coreFileUnreadable;

  /// No description provided for @coreStateFileSetAside.
  ///
  /// In fr, this message translates to:
  /// **'Fichier illisible mis de côté ({path}) : {detail}'**
  String coreStateFileSetAside(String path, String detail);

  /// No description provided for @coreScanFolderNotFound.
  ///
  /// In fr, this message translates to:
  /// **'dossier introuvable'**
  String get coreScanFolderNotFound;

  /// No description provided for @coreScanUnsupportedCompression.
  ///
  /// In fr, this message translates to:
  /// **'compression non prise en charge'**
  String get coreScanUnsupportedCompression;

  /// No description provided for @coreScanInstallSevenZip.
  ///
  /// In fr, this message translates to:
  /// **'Installer 7zip (paquet p7zip ou 7zip) pour lire les archives .7z.'**
  String get coreScanInstallSevenZip;

  /// No description provided for @coreScanUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'illisible : {detail}'**
  String coreScanUnreadable(String detail);

  /// No description provided for @coreSaveNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Save introuvable.'**
  String get coreSaveNotFound;

  /// No description provided for @coreEmuExited.
  ///
  /// In fr, this message translates to:
  /// **'{name} s’est arrêté avec le code {code}\n{output}'**
  String coreEmuExited(String name, int code, String output);

  /// No description provided for @coreEmuNotConfigured.
  ///
  /// In fr, this message translates to:
  /// **'Émulateur non configuré.'**
  String get coreEmuNotConfigured;

  /// No description provided for @coreEmuArchiveNotSupported.
  ///
  /// In fr, this message translates to:
  /// **'{name} ne lance pas les ROMs en archive dans RomSync : choisis melonDS pour ce jeu, ou décompresse la ROM.'**
  String coreEmuArchiveNotSupported(String name);

  /// No description provided for @coreEmuFlatpakLinuxOnly.
  ///
  /// In fr, this message translates to:
  /// **'Le mode Flatpak n’existe que sous Linux : indique l’exécutable de {name}.'**
  String coreEmuFlatpakLinuxOnly(String name);

  /// No description provided for @coreEmuExecutableNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Exécutable {name} introuvable : « {path} ». Indique son chemin dans les réglages.'**
  String coreEmuExecutableNotFound(String name, String path);

  /// No description provided for @coreEmuExecutableNotFoundLinux.
  ///
  /// In fr, this message translates to:
  /// **'Exécutable {name} introuvable : « {path} ». Indique son chemin dans les réglages, ou choisis le mode Flatpak.'**
  String coreEmuExecutableNotFoundLinux(String name, String path);

  /// No description provided for @coreEmuFlatpakMissing.
  ///
  /// In fr, this message translates to:
  /// **'Flatpak n’est pas installé sur ce système.'**
  String get coreEmuFlatpakMissing;

  /// No description provided for @coreEmuFlatpakAppMissing.
  ///
  /// In fr, this message translates to:
  /// **'Le Flatpak {id} n’est pas installé.'**
  String coreEmuFlatpakAppMissing(String id);

  /// No description provided for @coreEmuFlatpakNoWrite.
  ///
  /// In fr, this message translates to:
  /// **'Le Flatpak {name} n’a pas accès en écriture au dossier {folder}.'**
  String coreEmuFlatpakNoWrite(String name, String folder);

  /// No description provided for @coreEmuFlatpakNoRead.
  ///
  /// In fr, this message translates to:
  /// **'Le Flatpak {name} n’a pas accès au dossier de ROMs {folder}.'**
  String coreEmuFlatpakNoRead(String name, String folder);

  /// No description provided for @coreDesmumeExecutableNeeded.
  ///
  /// In fr, this message translates to:
  /// **'Indique l’exécutable de DeSmuME : son dossier Battery est défini dans le desmume.ini à côté de lui.'**
  String get coreDesmumeExecutableNeeded;

  /// No description provided for @coreDesmumeBatteryNotFound.
  ///
  /// In fr, this message translates to:
  /// **'Dossier Battery de DeSmuME introuvable : lance DeSmuME une fois, ou choisis le dossier dans les réglages.'**
  String get coreDesmumeBatteryNotFound;

  /// No description provided for @coreDesmumeBatteryAmbiguous.
  ///
  /// In fr, this message translates to:
  /// **'Plusieurs dossiers Battery de DeSmuME ({folders}) : choisis le bon dans les réglages.'**
  String coreDesmumeBatteryAmbiguous(String folders);

  /// No description provided for @coreDesmumeBatteryUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Dossier Battery de DeSmuME inconnu.'**
  String get coreDesmumeBatteryUnknown;

  /// No description provided for @coreMelonConfigUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'Configuration de melonDS illisible ({detail}) : les saves sont supposées à côté des ROMs.'**
  String coreMelonConfigUnreadable(String detail);

  /// No description provided for @coreMelonRelativeDir.
  ///
  /// In fr, this message translates to:
  /// **'melonDS utilise un dossier de saves relatif ({value}) : indique le dossier réel dans les réglages.'**
  String coreMelonRelativeDir(String value);

  /// No description provided for @coreRetroarchConfigNotFound.
  ///
  /// In fr, this message translates to:
  /// **'retroarch.cfg introuvable : lance RetroArch une fois, ou indique le dossier des saves dans les réglages.'**
  String get coreRetroarchConfigNotFound;

  /// No description provided for @coreRetroarchDefaultDir.
  ///
  /// In fr, this message translates to:
  /// **'RetroArch utilise son dossier de saves par défaut, qui dépend de son paquet : vérifie où il écrit les .srm.'**
  String get coreRetroarchDefaultDir;

  /// No description provided for @coreRetroarchSaveDirUnknown.
  ///
  /// In fr, this message translates to:
  /// **'Dossier des saves de RetroArch inconnu.'**
  String get coreRetroarchSaveDirUnknown;

  /// No description provided for @coreRetroarchCoreMissing.
  ///
  /// In fr, this message translates to:
  /// **'Cœur {core} introuvable : installe-le depuis RetroArch (Menu principal > Charger un cœur > Télécharger un cœur > « {entry} »).'**
  String coreRetroarchCoreMissing(String core, String entry);

  /// No description provided for @coreRetroarchCoreMissingAt.
  ///
  /// In fr, this message translates to:
  /// **'Cœur {core} introuvable ({path}) : installe-le depuis RetroArch (Menu principal > Charger un cœur > Télécharger un cœur > « {entry} »).'**
  String coreRetroarchCoreMissingAt(String core, String entry, String path);

  /// No description provided for @coreSourceSetting.
  ///
  /// In fr, this message translates to:
  /// **'réglage RomSync'**
  String get coreSourceSetting;

  /// No description provided for @coreSourceDesmumeLinux.
  ///
  /// In fr, this message translates to:
  /// **'dossier fixe de DeSmuME sous Linux'**
  String get coreSourceDesmumeLinux;

  /// No description provided for @coreSourceMelonDefault.
  ///
  /// In fr, this message translates to:
  /// **'valeur par défaut de melonDS (à côté de la ROM)'**
  String get coreSourceMelonDefault;

  /// No description provided for @coreSourceMgbaDefault.
  ///
  /// In fr, this message translates to:
  /// **'valeur par défaut de mGBA (à côté de la ROM)'**
  String get coreSourceMgbaDefault;

  /// No description provided for @coreSourcePath.
  ///
  /// In fr, this message translates to:
  /// **'{path}'**
  String coreSourcePath(String path);

  /// No description provided for @coreNoticeNewerSave.
  ///
  /// In fr, this message translates to:
  /// **'{title} : une save plus récente vient de {device}. Lance le jeu depuis RomSync pour la récupérer.'**
  String coreNoticeNewerSave(String title, String device);

  /// No description provided for @coreNoticeNewerSaveWebsite.
  ///
  /// In fr, this message translates to:
  /// **'{title} : une save plus récente vient de l’import sur le site. Lance le jeu depuis RomSync pour la récupérer.'**
  String coreNoticeNewerSaveWebsite(String title);

  /// No description provided for @coreUpdateSignatureUnreadable.
  ///
  /// In fr, this message translates to:
  /// **'Signature illisible : mise à jour refusée.'**
  String get coreUpdateSignatureUnreadable;

  /// No description provided for @coreUpdateSignatureInvalid.
  ///
  /// In fr, this message translates to:
  /// **'Signature invalide : cette mise à jour ne vient pas de RomSync, elle est refusée.'**
  String get coreUpdateSignatureInvalid;

  /// No description provided for @coreUpdateNotListed.
  ///
  /// In fr, this message translates to:
  /// **'{file} ne figure pas dans SHA256SUMS : mise à jour refusée.'**
  String coreUpdateNotListed(String file);

  /// No description provided for @coreUpdateHashMismatch.
  ///
  /// In fr, this message translates to:
  /// **'Le fichier téléchargé est altéré (hash différent) : mise à jour refusée.'**
  String get coreUpdateHashMismatch;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fr'].contains(locale.languageCode);

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
