# Tests manuels de l'appli PC : mises à jour

À faire une fois par système (Linux, Windows, macOS) avec la première version
qui suit la 0.5.0 : la 0.5.0 s'installe à la main, les suivantes doivent
arriver par la mise à jour. La logique est testée automatiquement
(`update_manager_test.dart`, `romsync_updater_test.dart`) ; ces tests
vérifient ce qui dépend du système : remplacement du dossier ou du `.app`,
programme séparé sous Windows, redémarrage.

Préparation : serveur à jour avec le relais actif (`ROMSYNC_UPDATES` absent
ou `on`), appli installée dans un dossier à soi (pas `Program Files`).

| # | Action | Résultat attendu |
| --- | --- | --- |
| 1 | Une release plus récente existe ; lancer RomSync | Bannière « RomSync X est disponible » et une notification ; *Voir les notes* affiche les notes de version (ordre de mise à jour en tête) |
| 2 | *Plus tard* | Rien n'est téléchargé ; la bannière reste |
| 3 | *Télécharger* | Barre de progression, « Vérification de la signature… », puis « prête à être installée » ; aucun fichier de l'installation n'a changé |
| 4 | Lancer un jeu, puis *Installer et redémarrer* | « Partie en cours : la mise à jour s'installera à la fin de la partie » ; à la fermeture de l'émulateur, RomSync se ferme et redémarre dans la nouvelle version |
| 5 | Réglages → version affichée, puis *Rechercher une mise à jour* | Nouvelle version affichée ; « RomSync est à jour » ; le dossier `<installation>.old` a disparu |
| 6 | Couper le serveur avec un envoi en file, puis *Installer* | L'installation attend que la file soit vide |
| 7 | Désactiver « Rechercher les mises à jour automatiquement », relancer | Aucune vérification au démarrage |
| 8 | Installer l'appli dans un dossier non modifiable (ex. `/opt` appartenant à root), puis *Télécharger* | Message « Le dossier d'installation … n'est pas modifiable » ; rien n'est remplacé |
| 9 | Pointer l'appli vers un serveur 0.4.0 | Bannière « Le serveur RomSync … est trop ancien » ; un choix de divergence est refusé clairement, rien n'est envoyé |
| 10 | Windows : vérifier `%LOCALAPPDATA%\RomSync\updater.log` après une mise à jour | « updated … » puis « started … » |
