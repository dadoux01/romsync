# Tests manuels du homebrew 3DS

À faire sur une vraie console (2DS ou 3DS sous Luma3DS, TWiLight Menu++ et
nds-bootstrap), avec le serveur joignable sur le réseau local. Le cœur C est
testé automatiquement sous Linux (`make 3ds-test`, `make 3ds-e2e`) ; ces tests
vérifient ce qui dépend de la console : libctru, carte SD, Wi-Fi, TWiLight
Menu++ et YANBF.

Préparation : un jeu de test dont la save existe déjà sur le serveur depuis le
PC (melonDS), noté **jeu A** ; un jeu sans save nulle part, **jeu B**. Noter
l'heure du PC et celle de la console.

## 1. Installation et premier lancement

| # | Action | Résultat attendu |
| --- | --- | --- |
| 1.1 | Installer `romsync-<version>-3ds.cia` avec FBI, puis lancer RomSync depuis le menu HOME | L'icône et la bannière RomSync apparaissent (avec un court son à la sélection) ; l'appli démarre sur l'écran d'appairage |
| 1.2 | Sur le site, *Appareils → Ajouter un appareil* ; sur la console, saisir `http://192.168.1.68:8085`, le code, puis le nom « 2DS » | « Appairage réussi » ; sur le site, l'appareil « 2DS » apparaît avec la plateforme 3DS |
| 1.3 | Recommencer l'appairage avec un code déjà utilisé (réglages → *Appairer de nouveau*) | Message « Code expiré ou déjà utilisé » ; l'ancien appairage reste valable |
| 1.4 | Saisir une adresse sans `http://` (`192.168.1.68:8085`) | Acceptée (`http://` ajouté) |
| 1.5 | Vérifier `sd:/3ds/romsync/token.txt` depuis un PC | Le fichier contient le jeton en clair, sur une ligne |
| 1.6 | Au choix des dossiers, `sd:/roms/nds/` est proposé : répondre *Oui*, puis *Oui* pour les sous-dossiers | La liste des jeux s'affiche après la recherche |
| 1.7 | Réglages → *Dossiers de ROMs* → *X* : choisir un dossier vide avec le navigateur (A, B, X) | Message « Aucune ROM DS (.nds) trouvée dans … » au lieu d'une liste vide |
| 1.8 | Retirer ce dossier (*Y*) | Il disparaît ; la liste des jeux est inchangée |

## 2. Synchronisation au démarrage

| # | Action | Résultat attendu |
| --- | --- | --- |
| 2.1 | Premier démarrage avec le jeu A (save sur le serveur, pas sur la console) | Jeu A « à jour » ; le fichier existe dans `sd:/roms/nds/saves/<nom>.sav` ; détails : emplacement 0, dernière synchro |
| 2.2 | Jouer au jeu A dans TWiLight Menu++, sauvegarder en jeu, quitter, rouvrir RomSync | Jeu A envoyé (« à jour ») ; sur le site, nouvelle version active venant de « 2DS », datée de l'ouverture de RomSync |
| 2.3 | Ouvrir le jeu A dans melonDS sur le PC | La progression faite sur la console est là |
| 2.4 | Sauvegarder plus loin sur le PC, puis ouvrir RomSync sur la console | Save téléchargée ; une copie de l'ancienne save est dans `saves/.backup/` ; en jeu, la progression du PC est là |
| 2.5 | Lancer le jeu B dans TWiLight Menu++ (qui crée une save vide de 512 Kio), puis rouvrir RomSync | Pas d'erreur ; le jeu B apparaît sur le site (première save) ou reste « pas de save » si rien n'a été écrit |
| 2.6 | Après le test 2.4, relancer le jeu A dans TWiLight Menu++ sans sauvegarder, puis rouvrir RomSync | Aucune nouvelle version sur le site (le remplissage de TWiLight Menu++ est coupé par le serveur) |
| 2.7 | Ouvrir RomSync deux fois de suite sans jouer | Aucun envoi la seconde fois ; tous les jeux « à jour » |

## 3. Horloge

| # | Action | Résultat attendu |
| --- | --- | --- |
| 3.1 | Régler l'horloge de la console 3 heures en retard ; sauvegarder sur le PC ; puis jouer et sauvegarder sur la console ; ouvrir RomSync | La save de la console devient active ; sur le site, sa date est l'heure réelle d'ouverture de RomSync (pas 3 h plus tôt) |
| 3.2 | Couper le Wi-Fi, jouer, ouvrir RomSync, puis rallumer le Wi-Fi et rouvrir RomSync | La version envoyée garde l'heure corrigée du premier passage (hors ligne) |
| 3.3 | Remettre l'horloge à l'heure | Rien à signaler |

## 4. Hors ligne et erreurs réseau

| # | Action | Résultat attendu |
| --- | --- | --- |
| 4.1 | Wi-Fi coupé (bouton ou réglage), jouer au jeu A puis ouvrir RomSync | Démarrage rapide (pas d'attente par jeu) ; en-tête « Hors ligne : 1 envoi(s) en attente » ; jeu A « à envoyer » |
| 4.2 | Wi-Fi rallumé, serveur arrêté, ouvrir RomSync | « Hors ligne » après un délai court (environ 8 s) ; l'envoi reste en file |
| 4.3 | Serveur relancé, *R* (tout synchroniser) | L'envoi part ; une seule nouvelle version sur le site |
| 4.4 | Révoquer l'appareil sur le site, puis *R* | Message « Appareil non autorisé » ; *SELECT → Appairer de nouveau* refait l'appairage |

## 5. ROMs partageant un identifiant

| # | Action | Résultat attendu |
| --- | --- | --- |
| 5.1 | Copier une ROM sous un autre nom (`Jeu-patch.nds`) dans le dossier, rouvrir RomSync | Les deux ROMs sont « choix requis » et ne sont pas synchronisées |
| 5.2 | Sur `Jeu-patch.nds`, *Y* → *Séparer* → nom « jeu patch » | Identifiant `x:jeu-patch` dans les détails ; sa save est synchronisée à part ; l'autre ROM reste « choix requis » |
| 5.3 | Sur l'autre ROM, *Y* → *Partager* | Elle se synchronise avec l'identifiant de la cartouche |

## 6. Emplacements de save (`.sav1` à `.sav9`)

| # | Action | Résultat attendu |
| --- | --- | --- |
| 6.1 | Dans TWiLight Menu++, réglages du jeu A → numéro de save 1 ; jouer et sauvegarder ; rouvrir RomSync | Détails : « Emplacement de save : 1 », fichier `.sav1` ; la save est envoyée |
| 6.2 | Copier une vieille save dans `<nom>.sav2`, régler le jeu A sur l'emplacement 2, rouvrir RomSync | Question « Emplacement de save changé » ; *Mettre de côté* : le fichier part dans `.backup` et la save du serveur est téléchargée dans `.sav2` |
| 6.3 | Refaire 6.2 en choisissant *Envoyer* | La vieille save est envoyée ; sur le site elle apparaît (conflit possible), l'autre version reste dans l'historique |
| 6.4 | Revenir à l'emplacement 0 | La save `.sav` est synchronisée normalement |

## 7. Emplacement des saves de TWiLight Menu++

| # | Action | Résultat attendu |
| --- | --- | --- |
| 7.1 | Dans TWiLight Menu++, régler l'emplacement des saves « dossier de la ROM » ; rouvrir RomSync | Détails : save à côté de la ROM ; la save du serveur y est téléchargée si besoin |
| 7.2 | Régler « dossier de TWiLight Menu++ » | Save dans `sd:/_nds/TWiLightMenu/saves/` |
| 7.3 | Remettre « dossier saves » | Retour au comportement par défaut |

## 8. Lancement par YANBF (facultatif)

| # | Action | Résultat attendu |
| --- | --- | --- |
| 8.1 | Sans `sd:/_nds/ntr-forwarder/sdcard.nds` : *X* sur un jeu (version `.cia`) | Message « sdcard.nds est introuvable », avec où copier le pack ; rien n'est lancé |
| 8.1b | Avec `sdcard.nds` mais sans `bootstrap.cia` : *X* (version `.cia`) | Message « bootstrap.cia de YANBF n'est pas installé » |
| 8.2 | Installer `bootstrap.cia` et le pack de forwarders ; *X* sur le jeu A | Synchro, message « Démarrage du jeu », puis le jeu démarre par nds-bootstrap avec la bonne save |
| 8.3 | Sauvegarder en jeu, revenir au menu HOME, rouvrir RomSync | Save envoyée |
| 8.4 | Mettre `SAVE_LOCATION = 1` dans `[NTR-FORWARDER]` de `sd:/_nds/ntr_forwarder.ini` (TWiLight Menu++ restant sur « dossier saves ») ; *X* | Lancement bloqué, avec l'explication et la valeur à mettre |
| 8.5 | Régler un numéro de save différent pour le jeu dans le forwarder (maintenir Y au lancement d'un forwarder) ; *X* dans RomSync | Lancement bloqué : « Emplacement de save différent pour ce jeu » |
| 8.6 | Wi-Fi coupé, *X* | Avertissement « Serveur injoignable », puis le jeu se lance |
| 8.7 | Lancer le `.3dsx` depuis le Homebrew Launcher et faire *X* | La liste des titres n'est pas lisible depuis le Homebrew Launcher : RomSync tente le saut ; le jeu démarre, ou un message avec le code d'erreur dit de vérifier `bootstrap.cia` et d'installer RomSync en `.cia` |

## 9. Divers

| # | Action | Résultat attendu |
| --- | --- | --- |
| 9.1 | Lire les écrans | Les accents s'affichent correctement (é, è, à, ç…), aucun texte ne déborde de l'écran |
| 9.2 | Plus de 27 jeux dans la liste : Gauche/Droite | Défilement page par page |
| 9.3 | Réglages → copies `.backup` : 2 ; provoquer trois téléchargements du même jeu | Seules les 2 copies les plus récentes restent dans `.backup` |
| 9.4 | Bouton HOME pendant la liste, puis retour | L'appli reprend normalement |
| 9.5 | Un homebrew `.nds` dans le dossier de ROMs | Identifié par `h:<sha1>` ; au démarrage suivant, il n'est pas relu en entier (identifiant en cache, démarrage plus rapide) |
| 9.6 | Placer un profil `twilight.json` modifié dans `sd:/3ds/romsync/profiles/` | Il remplace celui intégré à l'appli (un profil invalide affiche « Profils de la carte SD ignorés ») |
