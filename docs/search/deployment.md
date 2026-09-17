# Déploiement PostgreSQL sur le VPS existant

Le script et les workflows sont prêts localement. Aucun déploiement ni changement
sur le VPS n’a été exécuté. Cette livraison utilise PostgreSQL seul, sans
Meilisearch et sans augmentation du serveur.

## Livraison par GitHub

Pousser sur `dev`, ouvrir une PR vers `main`, puis attendre tous les contrôles CI
avant de fusionner. Le merge déclenche le déploiement backend ; les changements
Flutter déclenchent aussi le workflow web existant. Les versions Android/iOS
restent à construire et publier depuis le MacBook. Voir la
[recette Flutter](flutter-checklist.md).

Le workflow transmet `scripts/deploy_backend.sh` depuis le commit GitHub, avec
le chemin du dépôt et le SHA exact. Il ne fait plus de `git pull` avant le script.
Les déploiements sont sérialisés, sans annulation automatique d’un déploiement
actif. Le timeout GitHub est de 120 minutes. La CI générale est indépendante du
workflow de déploiement : attendre ses résultats **sur la PR avant le merge**.

Le secret facultatif `VPS_DEPLOY_SCRIPT`, s’il est renseigné, doit maintenant
être un chemin dans le checkout GitHub (par défaut `scripts/deploy_backend.sh`),
et non un chemin absolu sur le VPS. Un script personnalisé doit accepter la même
interface via stdin : chemin du dépôt, puis SHA complet.

## Ce que fait automatiquement le script

1. Verrouille le déploiement, vérifie les outils, le virtualenv existant, la
   configuration PostgreSQL et le checkout `main`. Refuse les modifications
   locales suivies et les commits divergents ou plus anciens.
2. Crée une sauvegarde PostgreSQL au format custom et vérifie que `pg_restore
   --list` peut lire son catalogue. Si cette étape échoue, le backend reste actif.
   Cette vérification n’est pas un test de restauration complète.
3. Suspend les trois timers du catalogue et attend la fin des imports en cours
   (cinq minutes maximum). Arrête backend et worker, puis avance le checkout
   jusqu’au SHA demandé et installe les dépendances.
4. Applique les migrations additives et lance `search_backfill` : champs
   normalisés, huit index SQL et statistiques. Les index laissés invalides par
   une interruption sont reconstruits. Les attentes de verrou DDL sont bornées
   à cinq secondes ; la durée totale du remplissage ne l’est pas.
5. Configure `SEARCH_BACKEND=postgres`, `SEARCH_INDEX_ENABLED=False`, installe
   le service `songspot-search-worker` avec les chemins et l’utilisateur du
   backend, et ajoute un fichier de configuration systemd au backend.
6. Collecte les fichiers statiques, exécute les contrôles Django, nettoie un lot
   d’événements locaux sans appel fournisseur et lance `search_health`.
7. Démarre backend et worker, vérifie leur état systemd, puis relance uniquement
   les timers auparavant actifs. Un état systemd actif ne remplace pas la recette
   fonctionnelle de l’application.

**Prévoir une interruption du backend au premier déploiement**, pendant les
migrations et le remplissage du catalogue. Sa durée sur le VPS n’a pas été
mesurée. Le script utilise le virtualenv existant ; il ne crée pas une release
parallèle. Aucun catalogue n’est réimporté ou purgé.

Les compléments Deezer restent activés si le réglage était absent, afin de
conserver la découverte de nouveaux titres. Un `SEARCH_ENRICHMENT_ENABLED=False`
explicite dans `.env` est conservé. Un lancement manuel peut imposer la valeur
avec `DEPLOY_SEARCH_ENRICHMENT_ENABLED=True` ou `False`. Le worker partage le
quota PostgreSQL avec les autres consommateurs Deezer et ne lance aucun moteur
externe. Ne pas utiliser `search_rebuild` pour cette livraison.

## Prérequis et fichiers de récupération

Le compte de déploiement doit être root ou disposer des droits `sudo -n` pour
arrêter/démarrer les services et installer leurs fichiers. `git`, `flock`,
`systemctl`, `pg_dump` et `pg_restore` sont nécessaires, avec un client PostgreSQL
compatible avec le serveur. Le rôle SQL doit pouvoir installer `unaccent`.
L’inspection SSH en lecture a confirmé root, les outils système et le service
`songspot` existant ; le script vérifie encore ces prérequis au lancement.

Le dossier privé `.deploy/` (mode 700, ignoré par Git) conserve, par exécution :

- `database.dump`, `previous-revision`, `target-revision` et `active-timers` ;
- les anciennes configurations `.env`, runtime et systemd quand elles existaient ;
- `configuration.json`, qui indique les chemins et les sauvegardes correspondantes.

`.deploy/search.env` contient les trois réglages de recherche et est chargé par
systemd après l’environnement habituel. Pour changer manuellement un réglage,
mettre à jour ce fichier **et** `.env`, puis redémarrer backend/worker. Les autres
secrets de `.env` sont conservés. Les sauvegardes ne sont pas automatiquement
purgées : prévoir leur espace disque et une rétention administrée séparément.

## Échec et reprise

Avant l’arrêt du backend, un échec restaure les timers suspendus. Après l’entrée
en maintenance, un échec laisse backend, worker et imports arrêtés pour éviter
de servir un catalogue partiellement préparé. Les journaux indiquent le dossier
de récupération. Corriger la cause puis relancer le déploiement ; le backfill
reprend les champs manquants et répare les index invalides. Après une telle
reprise, réactiver les timers consignés dans `active-timers` **du premier essai**,
car ils étaient déjà arrêtés au début de la nouvelle tentative.

Pour un retour arrière manuel autorisé : garder les consommateurs arrêtés,
restaurer le commit `previous-revision` et ses dépendances, puis les fichiers de
configuration selon `configuration.json`. Si un fichier systemd n’existait pas,
retirer uniquement ce fichier nouvellement créé. Recharger systemd et redémarrer
l’ancien backend et les timers précédemment actifs ; ne pas mélanger anciens et
nouveaux consommateurs Deezer. Conserver les migrations additives.

La sauvegarde SQL est un recours distinct : ne pas la restaurer automatiquement,
car cela supprimerait les écritures postérieures à son instantané. Elle est prise
avant la maintenance, alors que l’application peut encore écrire.

## Capacité et validation

Les [tests sur 3,78 millions de titres](postgres-scale.md) documentent CPU, mémoire,
disque et limites de qualité. Les quotas locaux ne reproduisent pas le CPU, le
stockage ou la charge des autres projets du VPS. Après livraison autorisée,
observer latences, erreurs SQL, mémoire disponible, espace disque et file de
compléments. Aucun benchmark ni requête de recherche créant des tâches n’a été
exécuté en production pendant cette préparation.

Les [vérifications locales](verification.md) couvrent l’orchestration simulée,
la syntaxe systemd réelle et la reprise d’index sur PostgreSQL réel. L’exécution
complète du script sur le VPS reste le futur déploiement autorisé par l’utilisateur.
