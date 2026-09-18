# Association de domaine pour l'autofill des mots de passe

Ces deux fichiers lient le site `songspot.eowinstudio.com` à l'app mobile
`com.songspot.app`. Une fois en place, un gestionnaire de mots de passe qui a
enregistré l'entrée du site la propose **directement** dans l'app, sans que
l'utilisateur ait à la chercher.

Sans eux, l'autofill fonctionne quand même — les champs sont annotés via
`autofillHints` (voir `songspot_mobile/test/autofill_test.dart`) — mais
l'utilisateur doit sélectionner l'entrée à la main.

| Fichier | URL finale | Plateforme |
|---|---|---|
| `assetlinks.json` | `https://songspot.eowinstudio.com/.well-known/assetlinks.json` | Android |
| `apple-app-site-association` | `https://songspot.eowinstudio.com/.well-known/apple-app-site-association` | iOS |

## État — vérifié le 2026-08-31

Les deux plateformes sont en place et validées en production.

| Contrôle | Résultat |
|---|---|
| `assetlinks.json` en ligne | 200, `application/json` |
| API Digital Asset Links de Google | 200, statement validée sur `02:48:F0:2F:…` |
| `apple-app-site-association` en ligne | 200, `application/json`, **0 redirection** |
| CDN Apple (`app-site-association.cdn-apple.com`) | 200, contenu à jour |
| Autofill iOS sur appareil | testé, fonctionnel |

Les sections qui suivent restent la référence pour refaire l'opération : rotation
d'une clé de signature, changement de domaine, ou remise en place après une
réinstallation du serveur.

---

## Partie 1 — iOS : activer la capability Associated Domains

L'entitlement est déjà dans `songspot_mobile/ios/Runner/Runner.entitlements` :

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>webcredentials:songspot.eowinstudio.com</string>
</array>
```

⚠️ **Un entitlement que l'App ID n'autorise pas fait échouer la signature.**
Tant que l'étape ci-dessous n'est pas faite, `fastlane ios testflight` cassera
sur `build_app` avec une erreur du type *"Provisioning profile ... doesn't
include the com.apple.developer.associated-domains entitlement"*.

Le projet est en `CODE_SIGN_STYLE = Automatic` : c'est Xcode qui déclare la
capability sur l'App ID, à condition de passer **une fois** par son interface.
Le `-allowProvisioningUpdates` du Fastfile régénère des profils, mais n'ajoute
pas une capability manquante — il faut donc bien faire ce premier passage à la
main, en local.

### Étapes

1. **Ouvrir le workspace** (le `.xcworkspace`, pas le `.xcodeproj`) :

   ```bash
   open songspot_mobile/ios/Runner.xcworkspace
   ```

2. Dans le navigateur de gauche, cliquer sur le projet **Runner** (l'icône bleue
   tout en haut), puis sur la target **Runner** dans la colonne du milieu.

3. Onglet **Signing & Capabilities**.

4. Vérifier que **Team** est bien réglé sur le compte correspondant au Team ID
   `WM42CA5NH5`, et que « Automatically manage signing » est coché.

5. Cliquer sur **+ Capability** (en haut à gauche de l'onglet), taper
   « Associated Domains », double-cliquer sur le résultat.

   Xcode ajoute la capability et, en tâche de fond, l'active sur l'App ID
   `com.songspot.app` dans le portail développeur. Il faut pour ça que le compte
   Apple connecté ait le rôle **Account Holder** ou **Admin** ; en rôle
   Developer, l'opération échoue silencieusement ou demande une validation.

6. Le champ **Domains** doit déjà afficher `webcredentials:songspot.eowinstudio.com`
   (Xcode lit le fichier d'entitlements existant). Si la liste est vide, ajouter
   la ligne à la main avec le `+`.

7. **Vérifier que Xcode n'a pas réécrit le fichier** — il lui arrive de
   reformater ou de dupliquer des clés :

   ```bash
   git diff songspot_mobile/ios/Runner/Runner.entitlements
   plutil -lint songspot_mobile/ios/Runner/Runner.entitlements
   ```

   Le seul changement attendu est aucun changement. `aps-environment` doit
   toujours être présent : s'il a disparu, les notifications push cassent.

8. **Confirmer côté portail** : sur
   [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list)
   → Identifiers → `com.songspot.app`, la ligne **Associated Domains** doit être
   cochée. Si elle ne l'est pas, la cocher manuellement, puis **Save**.

9. **Valider par un build local** avant de lancer la CI :

   ```bash
   cd songspot_mobile
   flutter build ios --release
   ```

   Sans `--no-codesign`, cette commande signe réellement : si la capability
   manque encore, l'erreur tombe ici plutôt que dans un run TestFlight.

### Test avant que le fichier soit en ligne

Apple sert les fichiers d'association via son CDN, avec un cache qui peut
prendre jusqu'à 24 h. Pour tester immédiatement contre le serveur, ajouter
temporairement `?mode=developer` au domaine :

```xml
<string>webcredentials:songspot.eowinstudio.com?mode=developer</string>
```

puis sur l'appareil : **Réglages → Développeur → Associated Domains Development**
(le menu Développeur n'apparaît qu'après avoir branché l'iPhone à un Xcode).
**Retirer `?mode=developer` avant tout build de release** — Apple rejette les
apps qui l'embarquent.

---

## Partie 2 — Héberger les deux fichiers

### 2.1 L'empreinte Android (déjà renseignée)

Play App Signing **est actif** sur cette app — la Play Console affiche
« Google Play gère et protège la clé de signature de votre appli pour vous »,
avec la clé de signature « En cours d'utilisation » sur 100 % des installations.
La clé d'upload n'est donc pas celle que les appareils vérifient.

`assetlinks.json` ne contient donc qu'une empreinte, celle de la **clé de
signature d'application** gérée par Google :

```
02:48:F0:2F:83:...:36:3D:CB:B3
```

C'est ce que vérifie un appareil qui installe l'app depuis Google Play. Rien à
modifier, sauf en cas de réinitialisation de la clé.

L'empreinte de la **clé d'upload** (`67:98:4B:9B:E3:…:A4:66`, celle du
`google-play-key.jks`) n'a volontairement pas été ajoutée : elle ne servirait
qu'à faire fonctionner l'association sur un `flutter build apk --release`
construit et installé à la main. Chaque empreinte listée ici délègue l'accès aux
identifiants du site à toute app portant ce nom de package et cette signature —
autant n'en déclarer aucune qui ne serve pas.

#### Tester l'association côté Android

Un build local (`flutter run`) est signé par la clé de debug, absente de ce
fichier : l'association ne s'y activera jamais. Ce n'est pas un problème à
diagnostiquer, c'est le comportement attendu.

Pour la tester, il faut un APK signé par Google, donc passer par un canal de
distribution Play — le **canal de test interne** suffit et ne publie rien
publiquement : les builds y passent par Play App Signing comme en production,
donc ils portent bien l'empreinte `02:48:…`.

À ne pas confondre pendant les tests en debug : l'autofill **fonctionne quand
même**. Les `autofillHints` sont dans l'app, donc le gestionnaire propose les
identifiants qu'il a enregistrés *depuis l'app*. Ce que l'association ajoute,
c'est le partage avec les identifiants enregistrés *depuis le site web*.

#### Où les retrouver

Play Console → **Test et versions** → **Intégrité de l'app** → page
**Signature d'application**. La page donne le certificat de clé d'importation,
et surtout un bloc **« Fichier JSON Digital Asset Links »** contenant un extrait
prêt à copier, avec l'empreinte de la clé de signature Google.

⚠️ **Cet extrait n'est pas utilisable tel quel ici.** Google le génère pour les
**Android App Links** (ouvrir l'app en cliquant un lien du site), avec la
relation :

```json
"relation": ["delegate_permission/common.handle_all_urls"]
```

L'autofill de mots de passe utilise une relation différente :

```json
"relation": ["delegate_permission/common.get_login_creds"]
```

C'est celle du fichier de ce dossier. Copier l'extrait de la Play Console tel
quel casserait l'autofill — seule l'empreinte est à reprendre, pas la relation.

Si un jour l'app gère les App Links (ouvrir `songspot.eowinstudio.com/...`
directement dans l'app, ce qui demande aussi des `intent-filter` avec
`android:autoVerify="true"` dans le manifeste), les deux relations peuvent
coexister dans le même objet :

```json
"relation": [
  "delegate_permission/common.get_login_creds",
  "delegate_permission/common.handle_all_urls"
]
```

#### Vérifier une empreinte depuis un appareil

Utile en cas de doute, ou après une réinitialisation de clé. L'APK installé
depuis le Store porte la signature réelle :

```bash
adb shell pm list packages -i com.songspot.app   # doit dire installer=com.android.vending

APK=$(adb shell pm path com.songspot.app | head -1 | tr -d '\r' | sed 's/^package://')
adb pull "$APK" /tmp/songspot-play.apk
~/Library/Android/sdk/build-tools/36.1.0/apksigner verify \
  --print-certs /tmp/songspot-play.apk | grep "SHA-256 digest"
```

`apksigner` sort l'empreinte en hex continu minuscule, `assetlinks.json` attend
des majuscules à deux-points :

```bash
echo "<empreinte>" | tr -d ':' | tr 'a-z' 'A-Z' | sed 's/../&:/g;s/:$//'
```

Un build sideloadé (`flutter run`, `adb install`) affiche `installer=null` et le
certificat `CN=Android Debug` : ce n'est pas la bonne empreinte.

### 2.2 Déposer les fichiers sur le VPS

Le repo est déjà cloné en `/var/www/songspot` sur le serveur, et le web root
statique est `/var/www/songspot-web` (voir `docs/WEB_DEPLOYMENT.md`).

```bash
ssh <user>@songspot.eowinstudio.com

cd /var/www/songspot && git pull

sudo mkdir -p /var/www/songspot-web/.well-known
sudo cp docs/well-known/assetlinks.json \
        docs/well-known/apple-app-site-association \
        /var/www/songspot-web/.well-known/
sudo chmod 644 /var/www/songspot-web/.well-known/*
```

### 2.3 Configurer nginx

Dans `/etc/nginx/sites-available/songspot`, ajouter ces deux blocs **au-dessus**
du `location /` qui proxifie vers Django (sinon Django répond 404) :

```nginx
# Association de domaine pour l'autofill des mots de passe (iOS + Android).
# Match exact `=` : priorité maximale, et aucun risque de capter
# /.well-known/acme-challenge/ utilisé par certbot.
location = /.well-known/assetlinks.json {
    root /var/www/songspot-web;
    default_type application/json;
}

location = /.well-known/apple-app-site-association {
    root /var/www/songspot-web;
    default_type application/json;
}
```

`root` (et non `alias`) laisse nginx concaténer l'URI complète, ce qui donne
bien `/var/www/songspot-web/.well-known/...`.

Le `default_type application/json` est indispensable pour
`apple-app-site-association` : le fichier **n'a pas d'extension**, donc nginx
le servirait en `application/octet-stream` et Apple le rejetterait. Ne pas
lui ajouter d'extension `.json` — Apple exige ce nom exact.

Recharger :

```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 2.4 Vérifier

```bash
# Android — doit renvoyer le JSON, en application/json, en 200
curl -sSL -D- https://songspot.eowinstudio.com/.well-known/assetlinks.json -o /dev/null
curl -s https://songspot.eowinstudio.com/.well-known/assetlinks.json | jq .

# iOS — 200, application/json, et surtout AUCUNE redirection.
# -I sans -L : un 301 ici signifie que c'est cassé, Apple ne suit pas les
# redirections sur ce fichier.
curl -sI https://songspot.eowinstudio.com/.well-known/apple-app-site-association
```

Validation par les outils des plateformes :

```bash
# Google vérifie la signature et le lien
curl -s 'https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://songspot.eowinstudio.com&relation=delegate_permission/common.get_login_creds' | jq .

# Ce que le CDN d'Apple a réellement mis en cache (peut prendre 24 h à se peupler)
curl -s https://app-site-association.cdn-apple.com/a/v1/songspot.eowinstudio.com | jq .
```

Sur l'appareil, l'association est résolue **à l'installation**, pas à chaque
lancement : après avoir mis les fichiers en ligne, désinstaller puis
réinstaller l'app pour la tester.

### 2.5 Rapport avec les déploiements automatiques

Ces deux fichiers sont **hors de tout workflow** : ni `web-deploy.yml` ni
`backend-deploy.yml` ne filtrent sur `docs/**`. Les mettre en ligne est une
opération manuelle, à refaire uniquement si une clé de signature change.

Ils survivent aux déploiements web : `web-deploy.yml` fait un
`rsync -az --delete` vers `/var/www/songspot-web/play/`, et `.well-known/` est
un **frère** de `play/`, pas un enfant — le `--delete` ne le voit pas.

Si `REMOTE_WEB_ROOT` était un jour remonté à `/var/www/songspot-web`, le
`--delete` emporterait `.well-known/` à chaque déploiement, et l'autofill se
dégraderait sans aucune erreur : les gestionnaires cesseraient simplement de
proposer l'entrée du site.
