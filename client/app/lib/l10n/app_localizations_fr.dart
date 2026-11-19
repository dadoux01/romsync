// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuler';

  @override
  String get later => 'Plus tard';

  @override
  String get save => 'Enregistrer';

  @override
  String get choose => 'Choisir';

  @override
  String get browse => 'Parcourir';

  @override
  String get retry => 'Réessayer';

  @override
  String get add => 'Ajouter';

  @override
  String get website => 'site web';

  @override
  String get dateTimePattern => 'dd/MM/yyyy HH:mm';

  @override
  String get decimalSeparator => ',';

  @override
  String sizeBytes(String n) {
    return '$n o';
  }

  @override
  String sizeKib(String n) {
    return '$n Kio';
  }

  @override
  String sizeMib(String n) {
    return '$n Mio';
  }

  @override
  String get serverUnreachable => 'Serveur injoignable.';

  @override
  String get language => 'Langue';

  @override
  String get languageSystem => 'Langue du système';

  @override
  String get trayOpen => 'Ouvrir RomSync';

  @override
  String get traySyncNow => 'Synchroniser maintenant';

  @override
  String get trayQuit => 'Quitter RomSync';

  @override
  String get pairTitle => 'Appairer cet appareil';

  @override
  String get pairIntro => 'Sur le site RomSync : Appareils → Ajouter un appareil, puis saisis le code ici.';

  @override
  String get pairServer => 'Adresse du serveur';

  @override
  String get pairServerRequired => 'Adresse du serveur requise';

  @override
  String get pairServerInvalid => 'Adresse invalide (ex. http://nas:8080)';

  @override
  String get pairCode => 'Code d’appairage';

  @override
  String get pairCodeInvalid => 'Code de 8 caractères (ex. K7QM-4XPA)';

  @override
  String get pairName => 'Nom de l’appareil';

  @override
  String get pairNameRequired => 'Nom requis';

  @override
  String get pairSubmit => 'Appairer';

  @override
  String get pairNoKeyringTitle => 'Aucun trousseau disponible';

  @override
  String get pairNoKeyringBody =>
      'RomSync range le jeton de l’appareil dans le trousseau du système (Secret Service : GNOME Keyring, KWallet, KeePassXC…), mais aucun ne répond dans cette session.\n\nTu peux démarrer un trousseau puis réessayer, ou stocker le jeton dans un fichier.';

  @override
  String get tokenFileWarning =>
      'Le jeton de cet appareil est stocké en clair dans un fichier (permissions 0600). Toute personne ou application ayant accès à ton compte peut le lire ; en cas de doute, révoque l’appareil depuis le site.';

  @override
  String get pairUseFile => 'Stocker le jeton dans un fichier';

  @override
  String get pairCodeExpired => 'Ce code a expiré ou a déjà été utilisé : génère-en un nouveau sur le site.';

  @override
  String get pairCodeUnknown => 'Code inconnu : vérifie-le, ou génère-en un nouveau sur le site.';

  @override
  String get rateLimited => 'Trop de tentatives : réessaie dans une minute.';

  @override
  String get pairUnreachable => 'Serveur injoignable : vérifie l’adresse et ta connexion (Tailscale ?).';

  @override
  String get homeRescan => 'Rescanner et synchroniser';

  @override
  String get settings => 'Réglages';

  @override
  String get homeUnauthorized => 'Cet appareil a été révoqué ou son jeton n’est plus valide : appaire-le à nouveau.';

  @override
  String get homePairAgain => 'Appairer à nouveau';

  @override
  String get homeOffline => 'Serveur injoignable : les parties se lancent avec les saves locales.';

  @override
  String homeOfflineQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count envois en attente',
      one: '1 envoi en attente',
    );
    return 'Serveur injoignable : les parties se lancent avec les saves locales, $_temp0.';
  }

  @override
  String homeRunning(String game) {
    return 'Partie en cours : $game. Chaque sauvegarde est envoyée automatiquement.';
  }

  @override
  String homeDivergence(String game) {
    return 'Choix à faire pour $game : deux appareils ont joué sans se synchroniser. Rien n’a été envoyé.';
  }

  @override
  String get homeAddFolder => 'Ajoute un dossier de ROMs dans les réglages.';

  @override
  String homeScanIssues(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers non lus',
      one: '1 fichier non lu',
    );
    return '$_temp0';
  }

  @override
  String get homeActivity => 'Activité récente';

  @override
  String get divergenceLocalSent => 'Save locale envoyée : c’est la save active.';

  @override
  String get divergenceServerTaken => 'Save du serveur récupérée ; ta save locale est dans l’historique.';

  @override
  String divergenceServerTakenBackup(String path) {
    return 'Save du serveur récupérée ; ta save locale est dans l’historique et dans $path.';
  }

  @override
  String get launchFailed => 'Lancement impossible';

  @override
  String staleTitle(String emulator) {
    return 'Une save $emulator existe déjà';
  }

  @override
  String get staleBody =>
      'RomSync ne l’a jamais synchronisée pour ce jeu : c’est probablement une ancienne partie.\n\nMise de côté (recommandé), elle est copiée dans le dossier .backup voisin, et la save du serveur sera téléchargée au prochain lancement.\nGardée, elle sera envoyée au serveur, qui gardera la plus récente des deux.';

  @override
  String get staleKeep => 'La garder';

  @override
  String get staleSetAside => 'La mettre de côté';

  @override
  String gameSharedNeedsChoice(int count, String id) {
    return '$count ROMs partagent l’identifiant $id : choisis pour celle-ci.';
  }

  @override
  String gameShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Save partagée avec $count autres ROMs',
      one: 'Save partagée avec 1 autre ROM',
    );
    return '$_temp0';
  }

  @override
  String get gameSeparate => 'Save séparée';

  @override
  String get gameModify => 'Modifier';

  @override
  String get gameEmulatorTooltip => 'Émulateur de ce jeu';

  @override
  String emulatorDefault(String name) {
    return '$name (par défaut)';
  }

  @override
  String emulatorNoArchives(String name) {
    return '$name — pas pour les archives';
  }

  @override
  String get history => 'Historique';

  @override
  String get play => 'Jouer';

  @override
  String get launchDownloaded => 'Save du serveur téléchargée.';

  @override
  String launchDownloadedBackup(String path) {
    return 'Save du serveur téléchargée ; l’ancienne copie locale est dans $path.';
  }

  @override
  String get notPaired => 'Appareil non appairé.';

  @override
  String get closeGameFirst => 'Ferme d’abord le jeu en cours : RomSync téléchargera ensuite la save du serveur.';

  @override
  String gameAlreadyRunning(String game) {
    return 'Une partie est déjà en cours : $game.';
  }

  @override
  String noticeNewSaveTitle(String title) {
    return 'Nouvelle save : $title';
  }

  @override
  String noticeChoiceTitle(String game) {
    return 'Choix à faire pour $game';
  }

  @override
  String get noticeChoiceBody =>
      'Deux appareils ont joué sans se synchroniser : rien n’a été envoyé. Ouvre RomSync pour choisir la save à garder.';

  @override
  String updateWaitGame(String game) {
    return 'Partie en cours ($game) : la mise à jour s’installera à la fin de la partie.';
  }

  @override
  String updateWaitQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count envois en attente',
      one: '1 envoi en attente',
    );
    return '$_temp0 : la mise à jour s’installera dès qu’ils seront partis.';
  }

  @override
  String updateWaitQueueHeld(int count, int held) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count envois en attente',
      one: '1 envoi en attente',
    );
    return '$_temp0, dont $held en attente de ton choix (divergence) : la mise à jour s’installera dès qu’ils seront partis.';
  }

  @override
  String get statusUpToDate => 'À jour';

  @override
  String get statusToUpload => 'À envoyer';

  @override
  String get statusToDownload => 'À télécharger';

  @override
  String get statusOffline => 'Hors ligne';

  @override
  String get statusNeedsChoice => 'Choix requis';

  @override
  String get statusDiverged => 'Choix à faire';

  @override
  String get statusUnavailable => 'Indisponible';

  @override
  String get statusNoSave => 'Pas de save';

  @override
  String get conflictResolved => 'Conflit résolu automatiquement';

  @override
  String get conflictResolvedTooltip =>
      'La dernière save envoyée ne partait pas de la version active : les deux sont dans l’historique du site.';

  @override
  String get copyCommand => 'Copier la commande';

  @override
  String get commandCopied => 'Commande copiée';

  @override
  String get settingsServer => 'Serveur';

  @override
  String settingsDevice(String name, String storage) {
    return 'Appareil « $name » · $storage';
  }

  @override
  String get tokenInKeyring => 'jeton dans le trousseau du système';

  @override
  String get tokenInFile => 'jeton dans un fichier (0600)';

  @override
  String get unpair => 'Désappairer';

  @override
  String get romFolders => 'Dossiers de ROMs';

  @override
  String get romFoldersHelp => 'Les .nds sont lus, y compris dans les .zip et les .7z (programme 7z, 7zz ou 7za).';

  @override
  String get addFolder => 'Ajouter un dossier';

  @override
  String get emulators => 'Émulateurs';

  @override
  String get systemNds => 'Nintendo DS';

  @override
  String get systemGba => 'Game Boy Advance';

  @override
  String get systemGb => 'Game Boy et Game Boy Color';

  @override
  String defaultEmulatorOf(String system) {
    return 'Émulateur par défaut ($system)';
  }

  @override
  String get defaultEmulator => 'Émulateur par défaut';

  @override
  String get defaultEmulatorHelp => 'Chaque jeu peut avoir le sien, depuis la liste des jeux.';

  @override
  String get tray => 'Barre système';

  @override
  String get keepInTray => 'Garder RomSync dans la barre système à la fermeture';

  @override
  String get keepInTrayHelp =>
      'Les saves des jeux lancés sans passer par RomSync sont alors envoyées automatiquement. Les saves plus récentes du serveur sont signalées par une notification, et téléchargées au prochain lancement depuis RomSync.';

  @override
  String get backups => 'Copies de sécurité';

  @override
  String get backupCount => 'Copies .backup gardées par save';

  @override
  String get backupHelp => 'Copie de la save locale remplacée par un téléchargement, dans un dossier .backup à côté.';

  @override
  String get updates => 'Mises à jour';

  @override
  String get autoUpdate => 'Rechercher les mises à jour automatiquement';

  @override
  String get autoUpdateHelp =>
      'Au démarrage puis toutes les 24 heures, auprès de ton serveur RomSync. Rien n’est installé sans ton accord.';

  @override
  String lastCheck(String date) {
    return 'Dernière vérification : $date';
  }

  @override
  String get seeUpdate => 'Voir la mise à jour';

  @override
  String get checkUpdate => 'Rechercher une mise à jour';

  @override
  String get emuDefault => 'par défaut';

  @override
  String get emuInUse => 'utilisé par certains jeux';

  @override
  String get emuFormatToCheck => 'format de save à vérifier';

  @override
  String get emuToConfigure => 'à configurer';

  @override
  String get emuExecutable => 'Exécutable';

  @override
  String get emuAppMac => 'Application (.app)';

  @override
  String get emuExeWindows => 'Exécutable (.exe)';

  @override
  String get emuExeLinux => 'Exécutable (nom dans le PATH ou chemin complet)';

  @override
  String get emuArgs => 'Arguments supplémentaires';

  @override
  String get emuSaveDir => 'Dossier des saves (vide : détecté)';

  @override
  String emuDetected(String where, String source) {
    return 'Détecté : $where (source : $source)';
  }

  @override
  String get emuDetectedRetroarch => 'selon la configuration de RetroArch';

  @override
  String get emuDetectedUnknown => 'inconnu';

  @override
  String get emuDetectedNextToRom => 'à côté de chaque ROM';

  @override
  String get chooseFolder => 'Choisir un dossier';

  @override
  String historyTitle(String title) {
    return 'Historique — $title';
  }

  @override
  String get historyRestoreOnSite => 'Restaurer sur le site';

  @override
  String get historyNoSave => 'Ce jeu n’a pas encore de save sur le serveur.';

  @override
  String get historyReadOnly =>
      'Lecture seule : pour restaurer une ancienne version, ouvre le jeu sur le site. L’appli la téléchargera avant la prochaine partie.';

  @override
  String get versionActive => 'active';

  @override
  String get versionDivergent => 'divergente';

  @override
  String get versionPinned => 'épinglée';

  @override
  String get versionClockFixed => 'horloge corrigée';

  @override
  String versionNote(String note) {
    return '« $note »';
  }

  @override
  String sizeTrimmed(String from) {
    return 'reçue en $from, remplissage coupé';
  }

  @override
  String sizeShrunk(String from, String to) {
    return 'taille du jeu passée de $from à $to';
  }

  @override
  String sizeForced(String from) {
    return 'taille forcée (avant : $from)';
  }

  @override
  String get olderVersions => 'Versions plus anciennes';

  @override
  String get choiceTitle => 'Plusieurs ROMs, un même jeu';

  @override
  String choiceSameId(String rom, String id) {
    return '« $rom » a le même identifiant ($id) que :';
  }

  @override
  String get choiceNotSynced => 'Tant que tu n’as pas choisi, cette ROM n’est pas synchronisée.';

  @override
  String get choiceShare => 'Partager la save';

  @override
  String get choiceShareHelp => 'Même progression que les autres ROMs de ce jeu (ROM patchée ou traduite).';

  @override
  String get choiceSeparate => 'Séparer';

  @override
  String get choiceSeparateHelp =>
      'Sa propre save sur le serveur, sous un identifiant que tu nommes (hack qui change la save).';

  @override
  String get choiceIdName => 'Nom de l’identifiant';

  @override
  String get choiceIdHelp => 'Lettres, chiffres et tirets, 32 caractères au plus';

  @override
  String choiceIdPreview(String id) {
    return 'Identifiant : $id';
  }

  @override
  String get choiceIdInvalid => 'Nom invalide : lettres sans accents, chiffres et tirets';

  @override
  String get validate => 'Valider';

  @override
  String get divTitle => 'Deux appareils ont joué sans se synchroniser';

  @override
  String divServer(String date, String from) {
    return '• Sur le serveur : save du $date, venant de $from.';
  }

  @override
  String get divFromWebsite => 'l’import sur le site';

  @override
  String get divLocalUnknown => '• Sur cet appareil : une autre save, modifiée depuis la dernière synchronisation.';

  @override
  String divLocal(String date) {
    return '• Sur cet appareil : save modifiée le $date, qui ne part pas de celle du serveur.';
  }

  @override
  String get divExplain =>
      'Envoyer ma save locale : elle devient la save active et les autres appareils la téléchargeront.\nPrendre celle du serveur : ta save locale est quand même envoyée, comme ancienne version (restaurable sur le site), puis remplacée par celle du serveur ; une copie reste dans le dossier .backup.';

  @override
  String get divCloseEmulator => 'Ferme d’abord l’émulateur s’il a encore ce jeu ouvert.';

  @override
  String get divLaterLaunch => 'Plus tard : rien n’est envoyé ni écrasé, et le jeu ne se lance pas.';

  @override
  String get divLater => 'Plus tard : rien n’est envoyé ni écrasé.';

  @override
  String get divTakeServer => 'Prendre celle du serveur';

  @override
  String get divSendLocal => 'Envoyer ma save locale';

  @override
  String updateCurrent(String version) {
    return 'Version actuelle : $version';
  }

  @override
  String get updateNoNotes => 'Pas de notes de version.';

  @override
  String get updateVerifiedInfo =>
      'Le téléchargement est vérifié (signature et empreinte) avant d’être proposé à l’installation. RomSync te demandera ton accord avant d’installer et de redémarrer.';

  @override
  String get download => 'Télécharger';

  @override
  String installTitle(String version) {
    return 'Installer RomSync $version ?';
  }

  @override
  String get installBody =>
      'RomSync va se fermer, installer la nouvelle version, puis redémarrer. Si l’installation échoue, la version actuelle reste en place. Pendant une partie ou avec des envois en attente, l’installation attend qu’ils soient terminés.';

  @override
  String get installRestart => 'Installer et redémarrer';

  @override
  String get updateAvailableDefault => 'Une nouvelle version est disponible.';

  @override
  String get seeNotes => 'Voir les notes';

  @override
  String compatServerTooOld(String version) {
    return 'Le serveur RomSync ($version) est trop ancien pour cette appli : mets d’abord à jour le serveur (nouvelle image Docker). En attendant, le choix en cas de divergence n’est pas disponible.';
  }

  @override
  String get compatOldVersion => 'version antérieure à 0.5.0';

  @override
  String compatClientTooOld(String version, String min) {
    return 'Cette appli ($version) est trop ancienne pour le serveur, qui demande au moins $min : mets-la à jour.';
  }

  @override
  String get updDev => 'Version de développement : pas de mise à jour automatique.';

  @override
  String get updNoPlatform => 'Pas de mise à jour pour ce système.';

  @override
  String get updPairFirst => 'Appaire d’abord cet appareil.';

  @override
  String updAvailable(String version) {
    return 'RomSync $version est disponible.';
  }

  @override
  String updNoticeTitle(String version) {
    return 'RomSync $version est disponible';
  }

  @override
  String get updNoticeBody => 'Ouvre RomSync pour lire les notes de version et installer la mise à jour.';

  @override
  String get updNoRelay =>
      'Le serveur ne propose pas de mise à jour (relais désactivé, serveur trop ancien ou aucune version publiée).';

  @override
  String updUpToDate(String version) {
    return 'RomSync est à jour ($version).';
  }

  @override
  String get updUnreachable => 'Serveur injoignable : vérification reportée.';

  @override
  String updCheckFailed(String detail) {
    return 'Vérification impossible : $detail';
  }

  @override
  String updDownloading(String version) {
    return 'Téléchargement de RomSync $version…';
  }

  @override
  String get updVerifying => 'Vérification de la signature…';

  @override
  String updNotWritable(String path) {
    return 'Le dossier d’installation ($path) n’est pas modifiable : installe la nouvelle version à la main, ou déplace RomSync dans un dossier à toi.';
  }

  @override
  String updReady(String version) {
    return 'RomSync $version est prête à être installée.';
  }

  @override
  String get updUnreachableDownload => 'Serveur injoignable pendant le téléchargement.';

  @override
  String updDownloadFailed(String detail) {
    return 'Téléchargement impossible : $detail';
  }

  @override
  String updInstallFailedWith(String detail) {
    return '$detail RomSync continue avec la version actuelle.';
  }

  @override
  String updInstallFailed(String detail) {
    return 'Installation impossible ($detail). RomSync continue avec la version actuelle.';
  }

  @override
  String get updInstalling => 'Installation…';

  @override
  String get updUpdaterMissing => 'romsync-updater.exe est introuvable.';

  @override
  String get coreSyncNeedsChoice => 'Deux appareils ont joué sans se synchroniser : choix à faire';

  @override
  String get coreSyncIdentical => 'Save identique à la version active';

  @override
  String get coreSyncArchived => 'Save locale archivée sur le serveur';

  @override
  String get coreSyncUploaded => 'Save envoyée';

  @override
  String get coreSyncUploadedDivergent => 'Save envoyée (divergence)';

  @override
  String get coreSyncUploadedNotActive => 'Save envoyée, mais une version plus récente reste active';

  @override
  String coreSyncOffline(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count envois en attente',
      one: '1 envoi en attente',
    );
    return 'Serveur injoignable : $_temp0';
  }

  @override
  String get coreSyncUnauthorized => 'Appareil non autorisé : appaire-le à nouveau.';

  @override
  String coreSyncRefused(String code, String detail, String copy) {
    return 'Envoi refusé ($code) : $detail. Copie conservée : $copy';
  }

  @override
  String get coreSyncQueued => 'Save mise en file d’attente';

  @override
  String get coreSyncUpToDate => 'Save à jour';

  @override
  String get coreSyncDownloaded => 'Save du serveur téléchargée';

  @override
  String get coreSyncOfflineLaunch =>
      'Serveur injoignable : la partie se lance avec la save locale, les envois partiront dès que le serveur répondra.';

  @override
  String coreSyncSharedId(String gameId) {
    return 'Plusieurs ROMs partagent l’identifiant $gameId : choisis d’abord de partager ou séparer leur save.';
  }

  @override
  String coreSyncServerTooOld(String version) {
    return 'Le serveur RomSync ($version) est trop ancien pour appliquer ce choix : rien n’a été envoyé ni écrasé. Mets d’abord à jour le serveur, puis recommence.';
  }

  @override
  String coreSyncServerTooOldForConsole(String version) {
    return 'Le serveur RomSync ($version) ne connaît pas encore cette console : la save attend dans la file. Mets d’abord à jour le serveur.';
  }

  @override
  String coreFileProblem(String file, String reason) {
    return '$file : $reason';
  }

  @override
  String coreFileBadFormat(String file, String detail) {
    return '$file : format inattendu ($detail)';
  }

  @override
  String get coreFileChanging => 'le fichier change pendant la lecture';

  @override
  String get coreFileStillWriting => 'le fichier est encore en cours d’écriture';

  @override
  String coreFileLocked(String detail) {
    return 'fichier verrouillé par un autre programme ($detail)';
  }

  @override
  String get coreFileUnreadable => 'lecture impossible';

  @override
  String coreStateFileSetAside(String path, String detail) {
    return 'Fichier illisible mis de côté ($path) : $detail';
  }

  @override
  String get coreScanFolderNotFound => 'dossier introuvable';

  @override
  String get coreScanUnsupportedCompression => 'compression non prise en charge';

  @override
  String get coreScanInstallSevenZip => 'Installer 7zip (paquet p7zip ou 7zip) pour lire les archives .7z.';

  @override
  String coreScanUnreadable(String detail) {
    return 'illisible : $detail';
  }

  @override
  String get coreSaveNotFound => 'Save introuvable.';

  @override
  String coreEmuExited(String name, int code, String output) {
    return '$name s’est arrêté avec le code $code\n$output';
  }

  @override
  String get coreEmuNotConfigured => 'Émulateur non configuré.';

  @override
  String coreEmuArchiveNotSupported(String name) {
    return '$name ne lance pas les ROMs en archive dans RomSync : choisis melonDS pour ce jeu, ou décompresse la ROM.';
  }

  @override
  String coreEmuFlatpakLinuxOnly(String name) {
    return 'Le mode Flatpak n’existe que sous Linux : indique l’exécutable de $name.';
  }

  @override
  String coreEmuExecutableNotFound(String name, String path) {
    return 'Exécutable $name introuvable : « $path ». Indique son chemin dans les réglages.';
  }

  @override
  String coreEmuExecutableNotFoundLinux(String name, String path) {
    return 'Exécutable $name introuvable : « $path ». Indique son chemin dans les réglages, ou choisis le mode Flatpak.';
  }

  @override
  String get coreEmuFlatpakMissing => 'Flatpak n’est pas installé sur ce système.';

  @override
  String coreEmuFlatpakAppMissing(String id) {
    return 'Le Flatpak $id n’est pas installé.';
  }

  @override
  String coreEmuFlatpakNoWrite(String name, String folder) {
    return 'Le Flatpak $name n’a pas accès en écriture au dossier $folder.';
  }

  @override
  String coreEmuFlatpakNoRead(String name, String folder) {
    return 'Le Flatpak $name n’a pas accès au dossier de ROMs $folder.';
  }

  @override
  String get coreDesmumeExecutableNeeded =>
      'Indique l’exécutable de DeSmuME : son dossier Battery est défini dans le desmume.ini à côté de lui.';

  @override
  String get coreDesmumeBatteryNotFound =>
      'Dossier Battery de DeSmuME introuvable : lance DeSmuME une fois, ou choisis le dossier dans les réglages.';

  @override
  String coreDesmumeBatteryAmbiguous(String folders) {
    return 'Plusieurs dossiers Battery de DeSmuME ($folders) : choisis le bon dans les réglages.';
  }

  @override
  String get coreDesmumeBatteryUnknown => 'Dossier Battery de DeSmuME inconnu.';

  @override
  String coreMelonConfigUnreadable(String detail) {
    return 'Configuration de melonDS illisible ($detail) : les saves sont supposées à côté des ROMs.';
  }

  @override
  String coreMelonRelativeDir(String value) {
    return 'melonDS utilise un dossier de saves relatif ($value) : indique le dossier réel dans les réglages.';
  }

  @override
  String get coreRetroarchConfigNotFound =>
      'retroarch.cfg introuvable : lance RetroArch une fois, ou indique le dossier des saves dans les réglages.';

  @override
  String get coreRetroarchDefaultDir =>
      'RetroArch utilise son dossier de saves par défaut, qui dépend de son paquet : vérifie où il écrit les .srm.';

  @override
  String get coreRetroarchSaveDirUnknown => 'Dossier des saves de RetroArch inconnu.';

  @override
  String coreRetroarchCoreMissing(String core, String entry) {
    return 'Cœur $core introuvable : installe-le depuis RetroArch (Menu principal > Charger un cœur > Télécharger un cœur > « $entry »).';
  }

  @override
  String coreRetroarchCoreMissingAt(String core, String entry, String path) {
    return 'Cœur $core introuvable ($path) : installe-le depuis RetroArch (Menu principal > Charger un cœur > Télécharger un cœur > « $entry »).';
  }

  @override
  String get coreSourceSetting => 'réglage RomSync';

  @override
  String get coreSourceDesmumeLinux => 'dossier fixe de DeSmuME sous Linux';

  @override
  String get coreSourceMelonDefault => 'valeur par défaut de melonDS (à côté de la ROM)';

  @override
  String get coreSourceMgbaDefault => 'valeur par défaut de mGBA (à côté de la ROM)';

  @override
  String coreSourcePath(String path) {
    return '$path';
  }

  @override
  String coreNoticeNewerSave(String title, String device) {
    return '$title : une save plus récente vient de $device. Lance le jeu depuis RomSync pour la récupérer.';
  }

  @override
  String coreNoticeNewerSaveWebsite(String title) {
    return '$title : une save plus récente vient de l’import sur le site. Lance le jeu depuis RomSync pour la récupérer.';
  }

  @override
  String get coreUpdateSignatureUnreadable => 'Signature illisible : mise à jour refusée.';

  @override
  String get coreUpdateSignatureInvalid =>
      'Signature invalide : cette mise à jour ne vient pas de RomSync, elle est refusée.';

  @override
  String coreUpdateNotListed(String file) {
    return '$file ne figure pas dans SHA256SUMS : mise à jour refusée.';
  }

  @override
  String get coreUpdateHashMismatch => 'Le fichier téléchargé est altéré (hash différent) : mise à jour refusée.';
}
