# SongSpot — migration vers un nouvel ordinateur

Ce document est la checklist de continuité de SongSpot : accès au dépôt, au
backend de production, à Firebase, à Google Play et à App Store Connect, puis
installation d'un poste de développement et de release.

> Ne jamais commiter les secrets listés ici. Les transférer par un gestionnaire
> de mots de passe avec pièces jointes chiffrées, ou par un support externe
> chiffré. Ne rendre l'ancien ordinateur qu'après avoir validé le nouveau.

## État du projet constaté le 27 août 2026

| Élément | Valeur actuelle |
|---|---|
| Dépôt | `git@github.com:Eowiin/SongSpot.git` |
| Compte GitHub CLI trouvé | `Ethan-dev27` — session locale expirée à renouveler |
| Branche de travail | `dev` |
| Branche de production backend | `main` |
| Backend public | `https://songspot.eowinstudio.com` |
| API / WebSocket | `https://songspot.eowinstudio.com/api` / `wss://songspot.eowinstudio.com` |
| Android package / iOS Bundle ID | `com.songspot.app` |
| Apple Team ID | `WM42CA5NH5` |
| Firebase | projet `songspot-c58e1`, numéro `774095310145` |
| Version Flutter de l'app | `2.1.5+42` |
| SDK Flutter installé sur l'ancien Mac | Flutter `3.41.4`, Dart `3.11.1` |
| Python utilisé en CI | Python `3.12` |
| Java constaté | Temurin JDK `17` |
| Fastlane verrouillé | `2.238.0` dans les `Gemfile.lock` |

Au moment de cet audit, la branche `dev` correspond à `origin/dev`, mais le
working tree comporte **25 fichiers modifiés et 10 entrées non suivies**. Ces
changements ne seront pas présents après un simple `git clone`.

Autres constats à traiter avant une release :

- aucune identité de signature iOS valide n'est actuellement trouvée dans le
  trousseau de ce Mac (`security find-identity -v -p codesigning`) ;
- l'entitlement iOS source contient `aps-environment=development` : contrôler
  l'entitlement de l'archive de distribution et la capacité Push dans Apple ;
- les sections IAP et publicité du backend sont actuellement commentées dans
  `songspot_backend/songspot/settings.py`. Les guides IAP/AdMob décrivent une
  cible de configuration, pas la preuve que ces fonctions sont actives sur la
  branche `dev` ;
- le compte `gh` local n'est plus authentifié. L'accès Git par SSH peut malgré
  tout fonctionner séparément.

## 1. À faire impérativement avant de rendre l'ancien ordinateur

### 1.1 Sauvegarder tout le code, y compris le travail non commité

Examiner d'abord les changements :

```bash
cd /Users/ethan/Personal/SongSpot
git status --short
git diff --stat
git diff
```

La méthode recommandée est de créer une branche de sauvegarde privée, de tout
commiter après revue, puis de la pousser :

```bash
git switch -c migration/old-mac-2026-08-27
git add -A
git commit -m "chore: sauvegarde avant migration de poste"
git push -u origin migration/old-mac-2026-08-27
git status --short
```

La dernière commande doit être vide. Ne pas utiliser seulement `git stash` :
un stash resté sur l'ancien Mac n'existe pas sur le nouveau.

Si le commit contient des changements qui ne doivent vraiment pas être poussés,
faire en plus une copie chiffrée de **tout le dossier**, `.git` inclus. Ne pas
mettre cette archive dans Dropbox/Drive en clair.

### 1.2 Sauvegarder les fichiers locaux non versionnés

Ces fichiers existent sur l'ancien Mac et doivent être transférés ou régénérés :

| Fichier actuel | Utilité | Action |
|---|---|---|
| `songspot_backend/.env` | configuration backend locale | transférer chiffré ou recréer |
| `songspot_backend/firebase-service-account.json` | envoi FCM depuis Django | de préférence régénérer une clé puis révoquer l'ancienne |
| `songspot_mobile/.env` | URL API/serveur/WebSocket | recréable sans secret |
| `songspot_mobile/android/key.properties` | mots de passe et chemin du keystore | transférer chiffré |
| `songspot_mobile/android/fastlane/google-play-key.jks` | **keystore d'upload Android** | sauvegarder à deux endroits chiffrés |
| `songspot_mobile/android/fastlane/google-play-key.json` | compte de service Play/Fastlane | transférer ou régénérer |
| `songspot_mobile/android/app/google-services.json` | configuration Firebase Android | retéléchargeable depuis Firebase |
| `songspot_mobile/ios/Runner/GoogleService-Info.plist` | configuration Firebase iOS | retéléchargeable depuis Firebase |
| `songspot_mobile/android/fastlane/.env` | configuration Sentry de release | transférer/recréer |
| `songspot_mobile/ios/fastlane/.env` | Sentry + clé App Store Connect en base64 | transférer/recréer avec précaution |

Le keystore Android actuel a les caractéristiques de contrôle suivantes :

```text
alias       : songspot
créé le     : 23 février 2026
SHA-1       : 27:52:AA:75:7F:24:28:35:E3:C0:6E:EF:95:26:73:1C:7D:96:64:E0
SHA-256     : 67:98:4B:9B:E3:59:C6:FB:04:52:75:4D:40:F8:86:CA:D2:30:90:EA:30:99:91:15:CE:74:09:4E:13:5D:A4:66
```

Vérifier le transfert sans révéler le contenu :

```bash
shasum -a 256 \
  songspot_mobile/android/fastlane/google-play-key.jks \
  songspot_mobile/android/fastlane/google-play-key.json \
  songspot_mobile/ios/Runner/GoogleService-Info.plist \
  songspot_mobile/android/app/google-services.json
```

Comparer les empreintes sur l'ancien et le nouveau poste. Faire ensuite
`chmod 600` sur `.env`, `.json`, `.plist`, `.jks` et `key.properties` sensibles.

Important : malgré son nom, `google-play-key.jks` est une clé de signature
Android ; `google-play-key.json` est une identité d'API Google. Les deux ne sont
pas interchangeables.

### 1.3 Vérifier la propriété de tous les comptes

Pour chaque service, vérifier sur l'ancien poste : identifiant de connexion,
adresse e-mail de récupération, rôle, 2FA, codes de secours, moyen de paiement
et présence d'au moins un second administrateur fiable.

| Service | Accès minimal à conserver |
|---|---|
| GitHub organisation/utilisateur `Eowiin` | admin du repo, Actions, secrets et branches protégées |
| Hébergeur du VPS | accès console/rescue, facturation, sauvegardes/snapshots |
| Registrar/DNS de `eowinstudio.com` | modification des enregistrements DNS |
| Apple Developer | équipe `WM42CA5NH5`, rôle permettant certificats/identifiants |
| App Store Connect | accès à SongSpot, TestFlight, soumissions, IAP, contrats/fiscalité |
| Google Play Console | accès à `com.songspot.app`, releases, App Signing et commandes |
| Google Cloud / Firebase | projet `songspot-c58e1`, IAM, FCM et clés de comptes de service |
| AdMob | compte éditeur `pub-2260442058102246`, apps Android et iOS |
| Sentry | projets backend/mobile, releases et jetons |
| Fournisseur SMTP | boîte/clé utilisée par les e-mails de reset |
| Grafana Cloud, si réellement activé | stack, token Alloy et alertes |

Stocker les codes 2FA de secours hors du Mac. Ne pas dépendre uniquement d'une
session navigateur encore ouverte ou d'un numéro de téléphone rendu avec le PC.

### 1.4 Sécuriser l'accès au VPS et les sauvegardes de production

Le repo ne contient pas l'adresse SSH certaine du VPS. L'IP
`77.42.85.235` figure dans la configuration CSRF locale, mais elle peut être
ancienne. La source de vérité est le DNS actuel, le portail de l'hébergeur et le
secret GitHub `VPS_HOST`.

Avant migration :

1. retrouver l'hébergeur et vérifier l'accès à sa console de secours ;
2. relever le user, port et chemin de l'application (normalement
   `/var/www/songspot`) ;
3. créer une **nouvelle** clé SSH sur le nouveau poste et ajouter uniquement sa
   clé publique à `~/.ssh/authorized_keys` sur le VPS ;
4. tester une nouvelle connexion avant de supprimer l'ancienne clé ;
5. vérifier les snapshots de l'hébergeur et faire une sauvegarde PostgreSQL ;
6. sauvegarder séparément les médias/stems utiles et les fichiers de
   configuration système.

Commandes de contrôle typiques sur le VPS :

```bash
sudo systemctl status songspot postgresql redis-server nginx
sudo journalctl -u songspot -n 100 --no-pager
sudo nginx -t
cd /var/www/songspot && git status && git remote -v
```

Sauvegardes à placer dans un stockage **chiffré**, hors du VPS :

```bash
sudo -u postgres pg_dump -Fc songspot > songspot-YYYY-MM-DD.dump
sudo tar -czf songspot-config-YYYY-MM-DD.tar.gz \
  /etc/nginx/sites-available/songspot \
  /etc/systemd/system/songspot.service
```

Ajouter, selon l'installation réelle :

- `/var/www/songspot/songspot_backend/.env` ;
- le credential FCM de production ;
- `/var/www/songspot/songspot_backend/media/` et les stems non reproductibles ;
- le service Celery, les timers/cron, la configuration Grafana Alloy ;
- la liste des paquets, la version PostgreSQL et les règles firewall.

Tester qu'un dump est lisible avec `pg_restore --list fichier.dump`. Une
sauvegarde non testée ne suffit pas.

### 1.5 Conserver les accès Apple réellement nécessaires

Il faut distinguer quatre éléments :

1. le compte Apple Developer/App Store Connect et son 2FA ;
2. la clé API App Store Connect utilisée par Fastlane
   (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_P8_FILE`) ;
3. le certificat et la clé privée de signature iOS dans le trousseau ;
4. la clé APNs chargée dans Firebase pour les notifications.

La clé `.p8` App Store Connect n'est téléchargeable qu'une fois lors de sa
création. Ici, sa version base64 est dans `songspot_mobile/ios/fastlane/.env`.
La transférer chiffrée ou créer une nouvelle clé App Manager/Admin, vérifier
Fastlane, puis révoquer l'ancienne.

Ce Mac ne présente actuellement aucune identité de signature valide. Sur le
nouveau Mac, se connecter dans Xcode à l'équipe `WM42CA5NH5`, activer
`Automatically manage signing`, puis laisser Xcode créer/télécharger le
certificat nécessaire. Si une ancienne clé privée doit absolument être
conservée, l'exporter avec son certificat en `.p12`, protégé par un mot de passe
fort ; un certificat seul sans clé privée ne permet pas de signer.

Vérifier enfin dans Firebase > Project settings > Cloud Messaging que la clé
APNs est toujours valide. Sa présence dans Firebase suffit à l'exécution ; il
faut surtout conserver l'accès Apple permettant de la remplacer.

### 1.6 Conserver l'accès Android réellement nécessaire

Dans Google Play Console > Setup > App integrity :

- confirmer que **Play App Signing** est activé ;
- noter séparément l'empreinte de la clé de signature gérée par Google et celle
  de la clé d'upload ;
- comparer l'empreinte d'upload avec le keystore listé plus haut ;
- vérifier que le compte de service Fastlane a accès à SongSpot et aux releases ;
- vérifier qu'au moins un compte humain est administrateur du Play Console.

Si le keystore d'upload est perdu et Play App Signing est actif, demander un
reset de clé d'upload. Sans Play App Signing, perdre la clé de signature peut
empêcher toute mise à jour de l'application existante.

## 2. Installation du nouveau poste

### 2.1 Choisir le système

Un **Mac est obligatoire pour compiler et signer iOS**. Windows ou Linux peut
servir au backend, au web et à Android, mais pas remplacer Xcode/Fastlane iOS.
Pour tout faire sur une seule machine, prendre un Mac Apple Silicon récent avec
assez d'espace pour Xcode, les simulateurs et les SDK Android.

### 2.2 Installer les outils

Sur macOS :

1. installer les mises à jour macOS ;
2. installer Xcode depuis l'App Store, l'ouvrir une fois et accepter la licence ;
3. installer les Command Line Tools : `xcode-select --install` ;
4. installer Homebrew ;
5. installer Git, GitHub CLI, Python 3.12, PostgreSQL, Redis, FFmpeg, JDK 17,
   Ruby/Bundler et CocoaPods ;
6. installer Android Studio, Android SDK, platform-tools et accepter les licences ;
7. installer Flutter stable `3.41.4` pour reproduire l'ancien environnement.

Exemple Homebrew, à adapter si certains outils sont déjà présents :

```bash
brew install git gh python@3.12 postgresql@16 redis ffmpeg temurin@17 \
  ruby cocoapods
```

Ajouter Flutter, Ruby Homebrew et Java au `PATH`, puis contrôler :

```bash
flutter --version
flutter doctor -v
flutter doctor --android-licenses
python3.12 --version
java -version
ruby --version
bundle --version
xcodebuild -version
```

Le repo ne verrouille pas encore Flutter via FVM. Éviter une mise à niveau de
Flutter/Xcode/Gradle en même temps qu'une première release depuis le nouveau Mac.

### 2.3 Configurer GitHub proprement

Créer une nouvelle clé par machine ; ne pas recopier la clé SSH personnelle de
l'ancien Mac sauf nécessité exceptionnelle :

```bash
ssh-keygen -t ed25519 -C "eowin.dev@gmail.com" -f ~/.ssh/songspot_github
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/songspot_github
pbcopy < ~/.ssh/songspot_github.pub
```

Ajouter la clé publique dans GitHub > Settings > SSH and GPG keys. Ajouter au
nouveau `~/.ssh/config` :

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/songspot_github
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
```

Puis :

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config ~/.ssh/songspot_github
chmod 644 ~/.ssh/songspot_github.pub
ssh -T git@github.com
gh auth login -h github.com -p ssh -w
git config --global user.name "Ethan SAUX"
git config --global user.email "eowin.dev@gmail.com"
git clone git@github.com:Eowiin/SongSpot.git
cd SongSpot
git fetch --all --prune
git switch dev
```

Si une branche `migration/old-mac-2026-08-27` a été créée, la récupérer avant
tout autre travail et vérifier que les modifications attendues y sont présentes.

## 3. Restaurer la configuration locale

Depuis le coffre/support chiffré, remettre les fichiers du tableau de la section
1.2 à leurs chemins exacts. Corriger le chemin `storeFile` dans
`songspot_mobile/android/key.properties` s'il est absolu ou si l'emplacement du
repo a changé.

Vérifier qu'aucun secret n'est suivi par Git :

```bash
git status --short --ignored
git ls-files '*.env' '*.p8' '*.p12' '*.jks' '*.keystore' \
  '*google-services.json' '*GoogleService-Info.plist' \
  '*firebase-service-account*.json' '*google-play-key*.json'
```

La deuxième commande ne doit afficher aucun credential réel.

Si l'on préfère régénérer :

- Firebase Android/iOS : Firebase Console > Project settings > General ;
- credential backend FCM : Google Cloud IAM > service account > Keys ;
- compte de service Play : Google Cloud IAM, puis accorder l'accès dans Play ;
- clé App Store Connect : Users and Access > Integrations > API ;
- token Sentry : Sentry > User/Auth tokens ou Internal Integrations.

Après validation des nouvelles clés, supprimer/révoquer les anciennes dans les
consoles correspondantes.

## 4. Lancer et vérifier le projet localement

### 4.1 Backend Django

```bash
cd SongSpot/songspot_backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
cp .env.example .env  # seulement si .env n'a pas été restauré
python manage.py migrate
python manage.py check
python manage.py test
daphne -b 0.0.0.0 -p 8000 songspot.asgi:application
```

Pour les WebSockets multi-process, tâches async et notifications :

```bash
brew services start redis
celery -A songspot worker -l info
```

Ne pas copier le `.env` de production sur le poste local sans nécessité. Le
local peut utiliser SQLite et des credentials dédiés au développement.

### 4.2 Flutter

Créer/restaurer `songspot_mobile/.env`. Pour la prod actuelle :

```env
SERVER_URL=https://songspot.eowinstudio.com
API_BASE_URL=https://songspot.eowinstudio.com/api
WS_BASE_URL=wss://songspot.eowinstudio.com
```

Puis :

```bash
cd SongSpot/songspot_mobile
flutter clean
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

Tester séparément un simulateur iOS, un appareil iOS réel, un émulateur Android
et au moins un vrai appareil. Les notifications, achats et Google Play Billing
doivent être testés sur les environnements Store appropriés, pas seulement en
debug local.

## 5. Accès et déploiement du backend de production

### Déploiement automatique

`.github/workflows/backend-deploy.yml` se déclenche lors d'un push sur `main`
qui touche le backend, `docker-compose.yml` ou `scripts/deploy_backend.sh`.
L'action se connecte au VPS, fait un `git pull --ff-only`, installe les
dépendances, exécute les migrations/collectstatic et redémarre `songspot`.

Secrets GitHub nécessaires :

| Secret | Rôle |
|---|---|
| `VPS_SSH_PRIVATE_KEY` | clé privée réservée au robot de déploiement |
| `VPS_HOST` | hôte/IP du VPS |
| `VPS_USER` | utilisateur SSH |
| `VPS_APP_DIR` | chemin du repo, normalement `/var/www/songspot` |
| `VPS_PORT` | port, défaut 22 |
| `VPS_HOST_KEY` | clé d'hôte épinglée, recommandé |
| `VPS_DEPLOY_SCRIPT` | optionnel, défaut `scripts/deploy_backend.sh` |

Ces secrets restent dans GitHub et n'ont pas besoin d'être copiés sur le nouveau
Mac. GitHub ne permet pas de relire leur valeur : si personne ne possède la
source, les faire tourner. Utiliser une clé SSH différente de la clé humaine.

Flux recommandé : branche feature → PR vers `dev` → tests → merge vers `main` →
surveiller Actions → vérifier la prod. Ne pas pousser sur `main` juste pour
tester le nouveau poste.

Contrôles après déploiement :

```bash
curl -fsS https://songspot.eowinstudio.com/app-ads.txt
curl -I https://songspot.eowinstudio.com/admin/
```

Puis vérifier connexion, création/join de room, audio, WebSocket, logs Sentry et
notifications. Consulter le workflow GitHub et `journalctl` en cas d'échec.

### Rafraîchissement du catalogue (obligatoire)

Le catalogue n'est plus une liste figée : les catégories se réalimentent depuis
les charts et playlists éditoriales Deezer. Sans le timer ci-dessous, les pools
cessent de se renouveler et les joueurs retombent sur les mêmes titres.

```bash
sudo cp scripts/systemd/songspot-refresh-catalog.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now songspot-refresh-catalog.timer
systemctl list-timers songspot-refresh-catalog.timer
```

Adapter `User=` et les chemins du `.service` à l'installation réelle. Premier
remplissage, à lancer une fois à la main après le déploiement (il dure plusieurs
minutes, l'API Deezer étant limitée à ~50 requêtes / 5 s par IP) :

```bash
sudo -u songspot .venv/bin/python manage.py refresh_catalog
```

Vérifier ensuite dans l'admin Django que chaque catégorie a un `refreshed_at`
récent et quelques centaines de titres au minimum.

Les seuils de qualité qui décident de ce que le jeu propose **de lui-même** se
règlent dans **Catalog settings**, sans redéploiement. Deux cas où ils ne
s'appliquent pas, volontairement :

- quand le joueur a choisi l'artiste : il l'a demandé, on le lui donne, même
  avec 200 fans ;
- quand la piste vient d'un chart ou d'une playlist éditoriale Deezer
  (`is_curated`) : la source a déjà fait ce tri, et mieux. Les compteurs de fans
  de Deezer reflètent son audience européenne, donc un seuil global vide les
  catégories des autres marchés — à 50 000 fans, « Top J-Pop » ne gardait que
  7 titres sur 61, et Bollywood 15 sur 100.

Ce qui reste filtré partout : il faut un extrait audio, pas de karaoké ni de
groupe de reprises, et pas de version alternative (live, remix, remaster).

**Choisir la source d'une catégorie.** Les charts Deezer (`/chart/{genre}`) sont
cadrés sur le pays de l'IP appelante. Il n'existe ni paramètre `country` ni
en-tête pour changer ça — les deux sont ignorés silencieusement — donc un serveur
en France reçoit des charts français, définitivement. Les playlists éditoriales,
elles, sont curées par genre et n'ont pas ce biais.

Règle : un chart de genre quand le public français *est* la cible (Pop, Rock,
Rap FR, Variété…), une playlist éditoriale quand le genre vit ailleurs. Le genre
2 « Musique africaine » lu depuis la France renvoyait Aya Nakamura en tête, avec
Shakira derrière : exact pour la France, mais ce n'est pas de l'Afrobeats.

Éviter les playlists « Top &lt;pays&gt; » de Deezer, qui semblent la réponse
évidente : elles sont périmées ou mal curées (Top South Korea s'ouvre sur deux
groupes allemands et six titres de Yiruma).

Après avoir modifié le mapping `SOURCES` d'une catégorie, la reconstruire —
sinon les entrées de l'ancienne source restent indéfiniment, les runs normaux
n'ajoutant jamais que du contenu :

```bash
python manage.py refresh_catalog --category afrobeats --replace
```

Le cache Redis est également requis en production : le catalogue interroge
Deezer, dont l'API publique plafonne à ~50 requêtes / 5 s **par IP**, et tout le
trafic sort par le VPS. Sans cache partagé entre workers, l'autocomplétion épuise
le quota dès que quelques joueurs tapent en même temps. Renseigner
`CACHE_REDIS_URL` (ou laisser `CHANNEL_LAYERS_REDIS_URL`, dont il se déduit).

Ce Redis alimente uniquement l'alias de cache `deezer`. Le cache `default` de
Django reste local et le restera : DRF y lit le throttling à chaque requête de
jeu et lève une exception s'il échoue — un `default` sur Redis ferait de Redis un
point de défaillance unique pour jouer tout court. Une panne Redis coûte donc de
la vitesse et du quota Deezer, rien d'autre : les accès au cache `deezer` sont
tous encapsulés, une erreur se lit comme un défaut de cache, et un disjoncteur
arrête d'appeler Redis pendant 30 s après trois échecs consécutifs.

En local, aucun Redis n'est nécessaire : laisser `CHANNEL_LAYERS_REDIS_URL` vide
suffit à basculer les deux caches en mémoire.

## 6. Release Android vers Google Play

### Première validation sur le nouveau poste

```bash
cd SongSpot/songspot_mobile
flutter pub get
cd android
bundle config set --local path vendor/bundle
bundle install
keytool -list -v \
  -keystore fastlane/google-play-key.jks \
  -alias songspot
```

Comparer SHA-1/SHA-256 avec la section 1.2 et avec Play Console. Vérifier aussi
que `key.properties` référence ce fichier et que les mots de passe fonctionnent.

### Commandes Fastlane actuelles

Depuis `songspot_mobile/android` :

```bash
bundle exec fastlane internal        # build AAB + upload test interne
bundle exec fastlane closed_testing  # promotion internal -> alpha
bundle exec fastlane production      # promotion alpha -> production
```

`bundle exec fastlane play_store` construit puis promeut directement en
production ; l'éviter pour la première release depuis une nouvelle machine.

Le Fastfile calcule automatiquement le prochain `versionCode` à partir des
tracks Play. La version marketing (`versionName`) vient de `pubspec.yaml`.
Configurer les notes via `RELEASE_NOTES_EN` et `RELEASE_NOTES_FR` si nécessaire.

Avant production :

- vérifier que les testeurs internes reçoivent et lancent la build ;
- vérifier Firebase/FCM, Sentry et les achats si présents dans cette branche ;
- contrôler Data safety, politique de confidentialité, suppression de compte,
  content rating, pays/prix et déclarations publicitaires ;
- contrôler les erreurs/pre-launch reports, puis promouvoir progressivement.

## 7. Release iOS vers TestFlight et App Store

### Première validation sur le nouveau Mac

1. Xcode > Settings > Accounts : se connecter au compte Apple autorisé ;
2. ouvrir `songspot_mobile/ios/Runner.xcworkspace`, jamais seulement le
   `.xcodeproj` ;
3. Runner > Signing & Capabilities : équipe `WM42CA5NH5`, bundle
   `com.songspot.app`, signature automatique ;
4. vérifier Push Notifications et Background Modes > Remote notifications ;
5. choisir un vrai iPhone et faire une build/run ;
6. vérifier `security find-identity -v -p codesigning` ;
7. restaurer `ios/fastlane/.env` avec les variables :
   `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_P8_FILE`, `SENTRY_DSN`,
   `SENTRY_ENVIRONMENT`, `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`.

Installer les dépendances :

```bash
cd SongSpot/songspot_mobile
flutter pub get
cd ios
pod install --repo-update
bundle config set --local path vendor/bundle
bundle install
```

### Commandes Fastlane actuelles

Depuis `songspot_mobile/ios` :

```bash
bundle exec fastlane testflight  # build, incrément auto, upload TestFlight
bundle exec fastlane app_store   # soumission en review, release manuelle
```

Le Fastfile prend le dernier numéro TestFlight et l'incrémente. Les notes
localisées utilisent `RELEASE_NOTES_EN` et `RELEASE_NOTES_FR`.

Faire d'abord TestFlight. Vérifier le traitement de la build, les informations
d'export compliance, les crashs, le login, le compte de démo pour la review,
les notifications sur appareil réel, la privacy manifest/fiche de confidentialité
et les IAP éventuels. Ensuite seulement lancer `app_store` et relire la fiche
App Store Connect avant validation finale.

## 8. Firebase, notifications, Sentry, AdMob et achats

### Firebase / notifications

- Android : `android/app/google-services.json` doit correspondre à
  `com.songspot.app`.
- iOS : `ios/Runner/GoogleService-Info.plist` doit correspondre au même bundle.
- Backend : `FCM_SERVICE_ACCOUNT_PATH` ou `FCM_SERVICE_ACCOUNT_JSON` doit être
  configuré ; avec l'architecture async, Redis et le worker Celery doivent
  réellement tourner.
- Firebase doit posséder une clé APNs valide pour les pushes iOS.

### Sentry

Le backend utilise `SENTRY_DSN`, `SENTRY_ENVIRONMENT` et `APP_VERSION`. Les
releases mobiles Fastlane exigent également `SENTRY_AUTH_TOKEN`, `SENTRY_ORG` et
`SENTRY_PROJECT` pour envoyer les symboles. Créer un token limité au strict
nécessaire, idéalement distinct par machine/CI.

### AdMob

Les App IDs versionnés sont :

- Android : `ca-app-pub-2260442058102246~1152808566` ;
- iOS : `ca-app-pub-2260442058102246~7067480229`.

Vérifier `app-ads.txt`, les ad units réelles, UMP/consentement, Data safety et la
fiche App Privacy avant activation. Ne jamais cliquer sur ses propres annonces
de production ; utiliser les IDs de test en développement.

### Achats intégrés

Les IDs prévus par la documentation sont :

```text
com.songspot.coins.500
com.songspot.coins.1200
com.songspot.coins.3000
com.songspot.coins.7000
```

Ne pas activer les achats en production sur la seule foi de `docs/IAP.md` : sur
la branche auditée, la configuration de vérification est commentée et doit être
réauditée de bout en bout. Une validation serveur réelle des reçus, les contrats
payants Apple, le profil marchand Google et des tests sandbox/licence sont
obligatoires avant ouverture.

## 9. Test final avant d'effacer l'ancien Mac

Tout doit être coché depuis le nouveau poste :

- [ ] clone, fetch, pull et push GitHub fonctionnent ;
- [ ] la branche de sauvegarde contient les 25 modifications et 10 entrées non suivies attendues ;
- [ ] tests backend et Flutter passent ;
- [ ] app Android debug fonctionne ;
- [ ] AAB signé accepté sur le track interne Play ;
- [ ] app iOS sur appareil réel fonctionne ;
- [ ] build acceptée dans TestFlight ;
- [ ] accès humain SSH au VPS avec la nouvelle clé ;
- [ ] accès console/rescue de l'hébergeur ;
- [ ] accès DNS et renouvellement du domaine ;
- [ ] accès GitHub Actions et secrets ;
- [ ] accès Apple Developer/App Store Connect et 2FA ;
- [ ] accès Play Console/Google Cloud/Firebase et 2FA ;
- [ ] accès Sentry, AdMob, SMTP et monitoring ;
- [ ] dump PostgreSQL et sauvegarde média/config copiés et testés ;
- [ ] les clés transférées ont les mêmes empreintes ;
- [ ] les nouvelles clés/credentials ont été testés avant révocation des anciens.

Ensuite : se déconnecter des comptes sur l'ancien Mac, révoquer ses sessions et
tokens propres à la machine, supprimer ses anciennes clés SSH des serveurs et de
GitHub, retirer le Mac du compte Apple si nécessaire, puis utiliser l'effacement
complet macOS. Ne jamais révoquer la clé Android qui signe les mises à jour ; la
conserver archivée même après effacement du poste.

## Guides détaillés du repo

- `docs/LOCAL_DEV_SETUP.md` et `docs/LOCAL_DEV_GUIDE.md`
- `docs/DEPLOYMENT_GUIDE.md`
- `docs/FASTLANE_SETUP.md` et `docs/RELEASES.md`
- `docs/PUSH_NOTIFICATIONS.md`
- `docs/SENTRY_SETUP.md`
- `docs/ADMOB_SETUP.md`
- `docs/IAP.md`
- `docs/GRAFANA_SETUP.md`

En cas de divergence, les fichiers exécutables actuels (`Fastfile`, workflows
GitHub, scripts de déploiement et code de settings) priment sur une ancienne
section documentaire.
