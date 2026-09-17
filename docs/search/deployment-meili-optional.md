> Variante historique optionnelle. Elle ne correspond plus au choix de livraison : voir [deployment.md](deployment.md). Aucun moteur supplémentaire ne sera installé dans la version PostgreSQL.

# Déploiement préparé, non exécuté

**Aucune écriture ni commande de déploiement n'a été exécutée en production.**
Le document décrit les opérations à autoriser. Ne pas exécuter les commandes de
test ou de benchmark sur `ssh songspot`, même sous une URL HTTP GET.

## Conditions avant activation

Les tests locaux sont disponibles dans `scripts/search_benchmark/README.md`.
Les mesures portent sur un catalogue beaucoup plus petit que la production.
Valider un export musical représentatif, borné et sans données personnelles,
sur un hôte isolé candidat avant de retenir sa mémoire/disque. Prévoir la place
pour PostgreSQL, l'index actif et sa reconstruction, et une génération précédente.
La reconstruction mesurée ne justifie pas l'installation de l'index complet sur
le VPS disposant de seulement 3,6 Gio libres lors de l'audit.

Le rôle PostgreSQL de migration doit pouvoir installer l'extension `unaccent`.
Le rôle applicatif doit accéder aux nouvelles tables. Tous les processus Deezer
partageant l'IP doivent utiliser la même base et le nouveau transport ; un ancien
cron encore actif utiliserait son ancien limiteur. Le plafond historique de
50 appels/5 secondes/IP n'est pas une garantie actuelle reconfirmée.

## Ordre exact des opérations à autoriser

1. Installer le moteur épinglé sur l'hôte validé avec
   `scripts/search_deploy/compose.yml`, volume persistant et clé privée.
   L'écoute par défaut est limitée à localhost. Pour un hôte séparé, configurer
   un réseau privé protégé et adapter `MEILI_URL` ; ne pas exposer le port public.
2. Préparer une nouvelle release backend et installer ses dépendances épinglées
   dans son virtualenv. Conserver l'ancienne release et son environnement.
   Sauvegarder PostgreSQL par la procédure existante. Suspendre les timers
   `songspot-crawl-artists`, `songspot-refresh-catalog`,
   `songspot-rebuild-catalog`, et attendre la fin des jobs actifs.
3. Depuis la nouvelle release, appliquer `python manage.py migrate` (0024 à
   0026 additives), puis `python manage.py search_backfill`. Cette commande
   travaille par lots de 500 et construit les index GIN/B-tree et l’index partiel des blocages avec
   `CREATE INDEX CONCURRENTLY`. Elle doit finir **avant le redémarrage du nouveau
   backend**, car la recherche PostgreSQL corrigée utilise ces champs. Employer
   un `lock_timeout` borné pour les migrations ; examiner/reprendre tout index
   invalide si une construction concurrente a été interrompue.
4. Ajouter les variables de `scripts/search_deploy/search.env.example` à
   l'environnement protégé. Garder `SEARCH_BACKEND=legacy`, `SEARCH_INDEX_ENABLED=True` et
   `SEARCH_ENRICHMENT_ENABLED=False`. Basculer la release et redémarrer
   `songspot.service` ; aucun test mutateur en production.
5. Lancer `python manage.py search_rebuild`. Noter les deux noms retournés : ils
   contiennent l'ancienne génération après la bascule. Un échec de reconstruction
   laisse la génération active en place et conserve l'outbox. Ne pas lancer deux
   commandes de reconstruction/consommation à la fois.
6. Installer `scripts/systemd/songspot-search-worker.service`, lancer
   `systemctl daemon-reload`, puis `systemctl enable --now songspot-search-worker`.
   L'unité reprend l'utilisateur root des unités existantes ; son accès fichier
   est restreint. Vérifier `python manage.py search_health` : backlog nul,
   champs complets et nombres de documents cohérents. Cette vérification est en
   lecture mais effectue des comptages : la planifier hors pic.
7. Après validation du classement et de la capacité sur l'hôte candidat, passer
   `SEARCH_BACKEND=meili`, activer éventuellement
   `SEARCH_ENRICHMENT_ENABLED=True`, et redémarrer backend/worker. Une comparaison
   en miroir ou une activation progressive reste une modification de production
   à autoriser. Réactiver les timers avec le nouveau code seulement.
8. Distribuer le mobile après validation de cette API compatible. Les clients
   distribués continuent à recevoir une liste ; les nouveaux utilisent `v=2`.
   Les signatures et publications App Store/Play Store nécessitent les circuits
   de livraison habituels, non exécutés ici.

Le présent travail n'exécute aucun de ces huit points à distance. L'autorisation
finale doit préciser l'hôte moteur et le périmètre d'activation retenu.

## Vérifications et supervision

- Journaux `search_request` : type, durée, résultat vide et dégradation ; calculer
  p50/p95/p99 par fenêtre, sans requête ni identifiant de joueur dans les labels.
- Journaux `search_enrichment` : type, état, classe d'erreur, tentatives.
- `search_health` : outbox, ancienneté, répartition des états, complétude.
- Superviser redémarrages du worker, erreurs Meilisearch, mémoire cgroup,
  espace disque et durée d'une reconstruction. Exporter ces journaux/mesures
  vers l'observabilité existante avant activation large.
- Le budget PostgreSQL conserve les appels des cinq dernières secondes. Les
  réservations sont atomiques et indépendantes du cache Redis. Priorités :
  fond jusqu'à 24 slots occupés, recherche jusqu'à 34, previews jusqu'à 40.
  Ces réserves sont une politique prudente, pas un débit garanti à chaque type.
- Positif : 7 jours ; absence confirmée : 6 heures ; échec : 2 à 256 secondes,
  plafonné à 300 ; bail : 60 secondes. Après huit échecs, la tâche reste
  `failed` sans nouvelle tentative automatique jusqu’à une nouvelle demande.
  Les nouvelles requêtes précèdent les reprises, qui utilisent le budget de fond. Les anciens claims sont revalidés seulement
  lorsqu'ils sont redemandés, avec décalage déterministe de 0 à 299 secondes.
  Ne pas les purger globalement. Les appels HTTP du worker distinguent erreur
  et absence et n'utilisent pas de réponse périmée pour conclure à une absence.
- Les nouveaux clients effectuent au plus quatre requêtes par saisie, après le
  debounce initial de 350 ms. Après épuisement du rafraîchissement, ils invitent
  à réessayer au lieu d'afficher indéfiniment une recherche active.

## Retour arrière

Pour arrêter l'enrichissement : désactiver `SEARCH_ENRICHMENT_ENABLED`, redémarrer
backend/worker, puis arrêter le worker si nécessaire. Pour retirer le moteur du
chemin de requête : `SEARCH_BACKEND=postgres`, redémarrer le backend. La recherche
SQL complète, les UUID et les données musicales restent utilisables.

Pour revenir à l'ancienne release applicative : suspendre le nouveau worker,
restaurer l'ancienne release et son environnement puis redémarrer les services.
Ne pas remettre des clients Deezer anciens et nouveaux en concurrence. Le retour
à l'ancien transport perd la garantie du quota glissant et les corrections de
recherche ; privilégier le repli SQL du nouveau backend.

**Ne pas inverser les migrations ni supprimer les nouvelles tables pendant le
retour arrière.** Les colonnes additives sont ignorées par l'ancien code. Les
triggers continuent à enregistrer les changements. Une génération ancienne
conservée n'a pas reçu les écritures suivantes : ne pas la réactiver aveuglément.
Reconstruire depuis PostgreSQL avant une nouvelle activation du moteur. Supprimer
les générations devenues inutiles seulement après vérification et autorisation.

## Vérification mobile sur le MacBook

Le poste de développement Linux ne détient pas `google-services.json` ; la
compilation Android initialement tentée a donc été arrêtée par le plugin Google
Services. Ce fichier n'a été ni inventé ni copié depuis la production. Les builds
Android/iOS se font habituellement sur le MacBook, conformément à la précision
de l’utilisateur.

La validation locale utilise Flutter **3.41.9 / Dart 3.11.5** :
`flutter pub get --enforce-lockfile`, `flutter analyze --no-pub` et
`flutter test --no-pub`. Le verrou `pubspec.lock` est inchangé.

Sur le MacBook configuré pour les builds existants : reprendre ces vérifications
avec un SDK compatible avec le verrou, puis les builds release habituels Android
et iOS. Vérifier manuellement les trois écrans, une saisie interrompue par une
nouvelle manche et le complément sans retaper, contre le backend de recette.
Ne publier aucune version magasin avant autorisation de livraison.
