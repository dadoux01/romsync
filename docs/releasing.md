# Publier une version

## Ordre de mise à jour

Serveur d'abord (nouvelle image, par exemple avec Dockge), puis les clients
(appli PC, homebrew 3DS). Les notes de chaque release le rappellent.

## Signature des releases

Chaque release contient `SHA256SUMS` (SHA-256 de chaque fichier publié) et
`SHA256SUMS.sig` : la signature Ed25519 de `SHA256SUMS`, encodée en base64 sur
une ligne. La clé publique est dans `keys/release-ed25519.pub` (32 octets en
base64) ; les applis l'embarquent et refusent une mise à jour dont la
signature ou le hash ne correspond pas.

Vérifier une release à la main :

```sh
{ printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'; base64 -d keys/release-ed25519.pub; } > pub.der
openssl pkey -pubin -inform DER -in pub.der -out pub.pem
base64 -d SHA256SUMS.sig > sig.bin
openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in SHA256SUMS -sigfile sig.bin
sha256sum -c SHA256SUMS
```

### Créer la clé (une seule fois)

```sh
openssl genpkey -algorithm ed25519 -out romsync-release.pem
openssl pkey -in romsync-release.pem -pubout -outform DER | tail -c 32 | base64   # → keys/release-ed25519.pub
```

Garder `romsync-release.pem` hors du dépôt (gestionnaire de mots de passe),
jamais dans un commit (`*.pem` est dans `.gitignore`).

### Environnement « release »

La clé privée n'est accessible qu'au job `sign` de `release.yml`, par
l'environnement GitHub `release`, réservé aux tags `v*` :

1. *Settings → Environments → New environment* : `release`.
2. *Deployment branches and tags* : *Selected branches and tags* → *Add
   deployment branch or tag rule* → type *Tag*, motif `v*`.
3. *Environment secrets → Add environment secret* : `RELEASE_SIGNING_KEY`,
   valeur = tout le contenu de `romsync-release.pem` (lignes `BEGIN`/`END`
   comprises). En ligne de commande :
   `gh secret set RELEASE_SIGNING_KEY --env release -R dadoux01/romsync < romsync-release.pem`
4. Supprimer le secret de dépôt du même nom (*Settings → Secrets and variables
   → Actions → Repository secrets*), ou
   `gh secret delete RELEASE_SIGNING_KEY -R dadoux01/romsync`.

Créer l'environnement **avant** le prochain tag : un job qui cite un
environnement inexistant le crée sans aucune règle.

Le job `sign` vérifie que la clé correspond à `keys/release-ed25519.pub`, signe,
puis vérifie la signature avec la clé publique ; la release échoue si le
secret manque ou ne correspond pas.

### Changer de clé

Les applis n'acceptent que la clé qu'elles embarquent. Pour en changer : publier
une version, signée avec l'ancienne clé, dont les applis embarquent les deux
clés ; puis signer les versions suivantes avec la nouvelle, et retirer
l'ancienne une version plus tard.

## Protections du dépôt

- *Settings → Rules → Rulesets → New ruleset → New branch ruleset* :
  nom `main`, *Enforcement status* : *Active*, *Target branches* : *Include
  default branch* ; règles : *Restrict deletions* et *Block force pushes*.
- *New ruleset → New tag ruleset* : nom `versions`, *Active*, *Target tags* :
  *Include by pattern* `v*` ; règles : *Restrict creations*, *Restrict
  updates*, *Restrict deletions*, *Block force pushes*. Ajouter son propre
  compte (ou le rôle *Repository admin*) dans *Bypass list* pour pouvoir
  créer les tags.
- *Settings → Actions → General* :
  - *Actions permissions* : *Allow dadoux01, and select non-dadoux01, actions
    and reusable workflows* → *Allow actions created by GitHub* et *Allow
    actions by Marketplace verified creators*. Si un run est ensuite refusé
    pour `subosito/flutter-action` ou `golangci/golangci-lint-action` (créateur
    non vérifié), l'ajouter dans *Allow specified actions*
    (`subosito/flutter-action@*, golangci/golangci-lint-action@*`) ;
  - *Fork pull request workflows from outside collaborators* : *Require
    approval for all outside collaborators* ;
  - *Workflow permissions* : *Read repository contents and packages
    permissions* (déjà le cas).

## Publier

1. CI verte sur `main`.
2. `git tag -a vX.Y.Z -m "RomSync X.Y.Z"` puis `git push origin vX.Y.Z`.
3. `release.yml` construit les clients, le homebrew 3DS et l'image, signe
   `SHA256SUMS`, puis publie la release. Un suffixe (`-rc1`) en fait une
   pré-version, que les mises à jour automatiques ignorent.
