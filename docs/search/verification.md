# Vérification locale — 14 septembre 2026

Le développement et les tests ont été réalisés exclusivement en local. Aucun
accès SSH, appel à l’API de production ou changement distant n’a été effectué.

| Contrôle | Résultat final |
|---|---|
| Suite backend complète, PostgreSQL 16 / Python 3.12 / Django 6.0.1 | 358 tests, OK |
| Cohérence des migrations | Aucun changement manquant |
| Ruff, configuration du dépôt | Aucun problème |
| Flutter 3.41.9 / Dart 3.11.5, analyse | Aucun problème |
| Suite Flutter complète | 96 tests, OK |
| Résolution Flutter avec `--enforce-lockfile` | Réussie ; `pubspec.lock` inchangé |
| Corpus synthétique, intégration | 310 assertions réussies |
| Corpus musical local, intégration | 200 assertions réussies |
| Intégration PostgreSQL + Meilisearch | Rollback, rejeu, retard, panne, suppression, blocage et pagination validés |
| Santé du catalogue local après indexation | 5 363 titres, 2 306 artistes, outbox vide, cinq index SQL valides |
| `git diff --check` | Aucun problème |

La suite backend comprend notamment le budget glissant partagé entre threads,
les priorités, les échecs de coordination, les délais réseau, la reprise des
baux et le plafond des tentatives automatiques. La réservation du quota restaure
les délais SQL de la transaction appelante, que le quota soit accordé ou épuisé.
Les blocages restent effectifs en jeu dirigé, même avec un cache déjà rempli.
Les tests de transport utilisent des réponses simulées : aucune saturation de
Deezer n’est effectuée.

Les tests mobiles couvrent le rafraîchissement borné, les réponses obsolètes,
l’annulation et les messages FR/EN. Les trois parcours intègrent ce mécanisme
commun : choix d’artiste, solo et duel.

## Reproduire les contrôles

Depuis la racine, préparer le conteneur et la base isolés selon le
[README du benchmark](../../scripts/search_benchmark/README.md), puis :

```sh
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner manage.py test --noinput
docker compose -p songspot-search -f scripts/search_benchmark/compose.yml run --rm runner manage.py makemigrations --check --dry-run
docker run --rm -v "$PWD:/workspace" -w /workspace/songspot_backend ghcr.io/astral-sh/ruff:latest check .
```

Depuis `songspot_mobile`, avec Flutter 3.41.9 :

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
```

Les journaux de cette session sont disponibles temporairement dans
`/tmp/songspot-backend-tests.log` et `/tmp/songspot-mobile-locked-tests.log`.
Les corpus et mesures pérennes sont versionnables dans ce dossier ; leurs
conditions et limites sont détaillées dans [decision.md](decision.md).

## Vérifications restant avant livraison

Les builds natifs Android/iOS et leur recette sur appareils doivent être faits
sur le MacBook habituellement configuré. Le build Android tenté ici est bloqué
par l’absence de `google-services.json` ; aucun fichier Firebase de remplacement
n’a été créé. Les tests Flutter ne certifient pas ces builds natifs.

La charge locale couvre 25 282 titres, huit clients et 930 recherches, avec un
p95 de 68,65 ms et un p99 de 91,84 ms. Elle ne valide pas le catalogue complet.
Il reste à mesurer un volume représentatif sur l’hôte candidat avant activation.
Le [déploiement et retour arrière](deployment.md) décrit la procédure distante,
qui nécessite l’autorisation explicite de l’utilisateur.

## Complément du 15 septembre : PostgreSQL seul et grand volume

Le choix de livraison a été révisé selon le budget de l’utilisateur. La suite
backend passe maintenant **364 tests**, après les corrections détectées sur
3,78 millions de titres. Huit index SQL sont contrôlés. Ruff, les migrations et
`git diff --check` passent. Les tests mobiles n’ont pas été relancés : aucun code
mobile n’a changé pendant ce complément.

Des inspections SSH exclusivement en lecture ont servi à choisir les quotas
locaux ; tous les tests et toutes les modifications restent locaux. Les résultats
et compromis de qualité sont détaillés dans [postgres-scale.md](postgres-scale.md).

## Automatisation du déploiement — 15 septembre 2026

- **365 tests backend réussis** sur PostgreSQL, dont la reconstruction d’un index
  concurrent invalide et le contrôle de santé sans moteur externe.
- **12 tests du script réussis** : ordre sauvegarde/arrêt/checkout/migrations,
  erreurs de sauvegarde, imports occupés, échec de backfill ou de santé, échec
  du worker, verrou, conservation des paramètres et exécution via stdin SSH.
- La syntaxe du service généré est vérifiée par `systemd-analyze verify` réel ;
  les commandes de services et le dump sont simulés dans ces tests du script.
- Ruff, `bash -n`, la lecture YAML des workflows, `makemigrations --check
  --dry-run` et `git diff --check` passent.

Un premier passage de la suite backend a échoué sur le test existant de limite
du classement. Une assertion de statut HTTP a été ajoutée au diagnostic ; la
suite complète suivante a passé. La cause de cet échec isolé n’est pas établie ;
aucune logique du classement n’a été changée.

Commandes de contrôle du script depuis la racine :

```sh
bash -n scripts/deploy_backend.sh
python3 -m unittest discover -s scripts/tests -v
```

Journaux temporaires : `/tmp/songspot-deploy-backend-tests.log` et
`/tmp/songspot-deploy-script-tests.log`. La CI inclut désormais ces tests du script
et une tâche PostgreSQL dédiée à la recherche et à la reprise du déploiement.
Aucun script de déploiement n’a été exécuté sur le VPS. Les essais Flutter
manuels restent décrits dans [flutter-checklist.md](flutter-checklist.md).

## Correctif best-of — 17 septembre 2026

Le mode solo Flutter sans jeton serveur comparait encore uniquement les UUID.
Il accepte maintenant une autre édition portant le même titre et le même
artiste (casse et espaces normalisés). La validation serveur reste utilisée
pour les parties avec jeton et pour le duel. Ce correctif de compatibilité ne
reproduit pas la normalisation serveur des mentions de remaster/remix.

Sept tests de non-régression passent : album/best-of, casse/espaces, autre
artiste, autre chanson, métadonnées manquantes et identifiant identique. Ils ont
été exécutés sur une copie du modèle et du test dans un projet temporaire avec
Flutter 3.35.5 / Dart 3.9.2, equatable 2.0.7. Le SDK 3.41.9 précédemment utilisé
dans /tmp n’était plus présent ; la suite complète de l’application n’a pas été
revalidée pour ce correctif. Les dépendances et le lockfile du projet restent
inchangés. La syntaxe du provider a été vérifiée par le formateur Dart sans
réécriture du fichier ; `git diff --check` passe. Recette et tests Flutter
complets à relancer sur le MacBook avant publication. Production non modifiée.
