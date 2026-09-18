# Refonte de la recherche SongSpot

Plan préparé le 14 septembre 2026, après analyse du code et de la production en lecture seule. Aucune correction ni migration n’a été appliquée pendant cette analyse.

## Objectif et périmètre

Permettre de retrouver les titres et artistes attendus, y compris avec ponctuation, accents, parenthèses, préfixes et fautes raisonnables, sans dépendre d’un appel Deezer à chaque frappe.

Parcours concernés : choix d’artiste, suggestions de réponse en solo et en duel. La validation des réponses et la sélection des extraits doivent rester cohérentes avec les résultats proposés.

La recommandation est un index de recherche dédié, alimenté par PostgreSQL, avec Deezer comme complément contrôlé. Typesense et Meilisearch sont les candidats à comparer sur un même corpus. Le choix définitif dépend des mesures ; PostgreSQL reste une alternative si le gain ne justifie pas l’exploitation d’un service supplémentaire.

## Autorisations et précautions opérationnelles

- Le développement, les fichiers de documentation et les tests isolés peuvent être faits localement.
- Production accessible par `ssh songspot`, **en lecture seule exclusivement** sans nouvelle autorisation explicite de l’utilisateur.
- Demander une autorisation avant toute écriture distante : fichier temporaire, installation, import, migration, indexation, modification Redis, changement de configuration, redémarrage ou déploiement.
- Un endpoint HTTP GET n’est pas nécessairement une lecture : les recherches actuelles écrivent des enrichissements, imports et compteurs. Ne pas les appeler en production pour un benchmark en lecture seule.
- Pour vérifier le classement en production, ne lancer que les fonctions de lecture inspectées, avec PostgreSQL forcé en lecture seule, timeout SQL borné et génération de bytecode Python désactivée. Ne pas exécuter `search_tracks`, `search_artists`, les imports ou les commandes de tests contre la production.
- Lire seulement les données musicales nécessaires. Ne pas exporter comptes, jetons, secrets ou données personnelles. Un export représentatif important se prépare avec un coût de lecture borné ; aucune extraction massive improvisée.
- Préparer un déploiement concret et réversible avant de demander son autorisation. Ne pas bloquer le développement local sur cette autorisation future.

## État observé, à dater plutôt qu’à considérer permanent

- Dépôt : `/home/eowin/projects/SongSpot`.
- Production : `/var/www/songspot`, backend et virtualenv dans `songspot_backend/`.
- Service : `songspot.service`, Daphne ; PostgreSQL 16 et Redis sur le VPS.
- Commit local analysé : `2347009e28cdcdc9c594be7a3caee737fd2b6b57`.
- Commit distant : `fb2cdd99577189aab835c348554bf98778e8ecf9` (merge contenant ce correctif).
- Empreintes identiques pour `catalog.py`, `matching.py`, `deezer_http.py`, `deezer_service.py`, `typos.py` entre local et production.
- Estimations `pg_stat_user_tables` : 3 725 148 titres et 778 434 artistes. Ce ne sont pas des comptages exacts ni des nombres de chansons uniques.
- Redis : 2 Go utilisés pour 2 Go maximum, politique `allkeys-lru`, environ 257 000 évictions cumulées. Pas de taux d’éviction mesuré.
- VPS : 7,6 Gio de RAM totale, environ 3,6 Gio disponibles à l’instant observé, aucun swap ; plusieurs autres services y tournent. Ne pas en déduire que l’index complet tiendra en mémoire.
- Une heure de journaux analysée : 2 114 recherches reconnues, toutes en HTTP 200, 67 listes vides, maximum de 94 recherches sur une minute. Ce n’est ni un test de charge ni une mesure exhaustive des échecs de pertinence.
- Fichier non suivi préexistant : `songspot_mobile/android/fastlane/google-play-key.jks:Zone.Identifier`. Ne pas le modifier ni l’inclure dans les changements.

Les documents `catalogue-refactor.md` et `catalogue-tests.md` décrivent des travaux antérieurs. Leur refus historique d’un worker externe et leur stratégie d’enrichissement opportuniste ne sont pas des contraintes de cette refonte. Préserver en revanche le fonctionnement des previews ; ne pas lancer leurs exemples de tests contre la production.

## Diagnostic et preuves

Les reproductions ci-dessous exécutent seulement sélection et classement locaux sur les données de production. Elles ne sont pas des tests HTTP de bout en bout ; l’enrichissement n’a pas été déclenché.

| Requête / contexte | Constat au 14 septembre | Attendu pour la refonte |
|---|---|---|
| `q&a`, titres | « Q&A » de Drake est premier après le dernier correctif | Conserver ce résultat ; exemple fourni par l’utilisateur |
| `Don't You (Forget About Me)` | Simple Minds présent en base mais rejeté par le filtre ; six autres suggestions | L’original doit rester accessible avec le titre complet |
| `Sweet Dreams (Are Made of This)` | Eurythmics rejeté ; deux autres interprètes proposés | L’original doit rester accessible |
| `nes`, titres | Les trois morceaux de NeS vérifiés sont absents des 40 résultats | Prioriser les morceaux de l’artiste exactement nommé |
| `nes`, artistes | NeS est correctement proposé | Préserver le correctif existant |
| `motion` | « The Motion » de Drake est absent des 40 ; présent avec `the motion` | Évaluer les titres proches avant les sous-chaînes de descriptions de bandes originales |
| `intro` | « INTRO » de Damso est candidat mais supprimé de la liste ; `intro damso` fonctionne | Permettre d’atteindre les autres artistes et affiner la recherche |
| `ed sheran`, `straykids` | Aucun candidat local ; claim de moins de sept jours, sans correspondance mémorisée | Correction locale des fautes/espaces et reprise possible après échec |
| `ac dc`, `cris mj`, `si veo a tu mama`, `a tu merced` | Fonctionnent lors de la reproduction malgré des SearchMiss historiques | Ne pas traiter les anciens misses comme des bugs toujours présents |

Causes identifiées :

1. `normalize_title()` supprime les parenthèses et invités pour identifier une chanson. `_query_filter()` cherche les mots courts uniquement dans ces champs appauvris : `me` ou `of` deviennent impossibles à retrouver. Les chaînes de recherche et d’identité doivent être distinctes.
2. `_candidates()` coupe à 150 enregistrements selon le rang, puis ajoute jusqu’à 50 titres normalisés exacts. Le classement final ne peut pas sauver les candidats déjà éliminés.
3. `_search_score()` privilégie popularité et audience ; un artiste exactement saisi n’a pas de priorité textuelle suffisante. Le bonus de titre exact est multiplicatif et peut être désactivé pour toute la liste si un artiste semble correspondre.
4. `_dedupe()` conserve au plus trois artistes par titre normalisé, supprimant des chansons légitimes. Le regroupement par noms normalisés peut aussi confondre des homonymes : ne pas reprendre ce modèle aveuglément.
5. Le seuil `ENRICH_BELOW = 5` mesure un nombre, pas la pertinence ni la couverture. Six mauvaises suggestions peuvent empêcher toute découverte Deezer.
6. L’enrichissement asynchrone ne met pas à jour la liste affichée si le joueur a fini de taper.
7. `DeezerService` transforme les erreurs en listes vides ; le claim est conservé sept jours. L’échec fournisseur, la tâche en cours et l’absence réelle sont confondus. Un arrêt du pool de threads peut aussi laisser un claim sans résultat.
8. L’import élimine les résultats sans preview alors que la disponibilité pour l’écoute et l’utilité comme réponse sont deux besoins distincts.
9. Le mobile dispose déjà d’un debounce de 350 ms et d’identifiants pour ignorer les réponses obsolètes. Préserver cela ; les exceptions deviennent aujourd’hui des listes vides.

### Quota Deezer : ce qui est vérifié et ce qui ne l’est pas

Une réponse de 2015 d’un développeur Deezer confirme **50 requêtes / 5 secondes / IP**, donc partagées entre les utilisateurs et processus sortant par le serveur. La documentation officielle actuelle redirige vers une authentification : ce plafond n’a pas été reconfirmé comme engagement actuel pour l’accès de SongSpot. Ne pas faire de test de saturation sur la production pour le vérifier.

Dimensionner prudemment pour 40 appels sur **toute fenêtre glissante** de cinq secondes, configuration ajustable si une source officielle accessible fournit une limite différente. Tous les consommateurs Deezer doivent partager ce budget, y compris previews, recherche et imports. Le budget quotidien moyen ne protège pas des rafales.

Le limiteur actuel utilise des fenêtres fixes : 40 appels avant une frontière et 40 après peuvent faire 80 appels sur une période courte. Le repli vers un cache par processus ne garantit plus une limite globale. Les entrées de coordination ne doivent pas dépendre d’un cache de réponses évictable.

## Architecture cible à valider

### Modèle de recherche

- PostgreSQL reste la source durable ; l’index peut être reconstruit.
- Deux collections logiques : artistes et chansons. Conserver les liens vers les enregistrements/éditions utilisés pour les extraits.
- Champs recherchables complets : titre original, forme normalisée conservant les mots significatifs, alias, artiste principal, contributeurs lorsque disponibles. Ajouter des variantes de ponctuation et espaces sans transformer des homonymes en une même entité.
- Identifiants stables d’artiste et de chanson/groupe d’éditions. Ne pas créer une identité universelle par simple suppression des parenthèses ; documenter les collisions et le traitement des remixes.
- Séparer `searchable`, règles de blocage, disponibilité audio et éligibilité à une manche. Une entrée sans preview peut être une proposition de réponse, sans devenir un morceau jouable.
- Toute chanson réellement jouable doit être recherchable avant d’être proposée dans une manche, ou disposer d’un repli local garantissant cette propriété pendant le retard d’indexation.
- Ne pas utiliser la réponse secrète de la manche pour manipuler le classement ni l’exposer dans les suggestions.

### Pertinence

Définir des niveaux lexicographiques ou équivalents : correspondance exacte normalisée, mots complets/proximité, préfixes, fautes, correspondances partielles. Popularité et audience départagent ensuite des correspondances comparables.

Préserver une diversité utile pour une requête ambiguë. Aucun titre populaire ne peut être universellement premier : `intro` n’identifie pas un artiste. Fournir affinage ou pagination pour atteindre les homonymes, et garantir une réponse pertinente pour `intro damso`.

### Complément Deezer

- Déclencher selon confiance textuelle, couverture/fraîcheur de la requête et budget, pas seulement selon le nombre de lignes locales. Définir et évaluer ces règles sur le corpus ; ne pas inventer un nouveau seuil arbitraire.
- Répondre rapidement avec l’index local ; exposer un état d’enrichissement lorsque nécessaire. Prévoir un complément borné pour une recherche inconnue.
- Dédupliquer les appels simultanés pour une même requête normalisée et les traiter dans un worker durable.
- États persistants : `pending`, `running` avec bail expirant, `succeeded`, `empty`, `failed` avec prochaine tentative. Durées séparées pour résultats positifs, absence confirmée et échec temporaire.
- Un crash, timeout ou quota dépassé doit permettre une reprise ; aucune erreur ne doit être mémorisée comme absence pendant sept jours.
- Limiteur atomique global glissant ; priorité aux extraits nécessaires aux joueurs, puis recherches interactives, puis travaux de fond. Budget de temps global réel incluant réseau, attente et retries : le `max_wait` actuel ne borne pas un appel réseau de dix secondes.
- Séparer stockage évictable des réponses et coordination fiable. Si le limiteur global est indisponible, servir le local et suspendre les appels externes non coordonnés.

### Synchronisation et contrat API

- Écritures musicales validées dans PostgreSQL, puis événements d’indexation durables (outbox transactionnelle ou mécanisme équivalent).
- Traitement idempotent, reprises, gestion des suppressions/blocages et versions pour éviter qu’un événement ancien écrase le nouveau.
- Construction d’un nouvel index versionné, rattrapage des événements, contrôle de complétude, puis bascule atomique. Garder l’index précédent pendant la validation.
- Préserver les identifiants et le contrat attendus par les clients déjà distribués. Le mobile attend actuellement une liste JSON ; ne pas la remplacer par un objet paginé sans versionnement/compatibilité.
- Nouvelle version de recherche pouvant exposer résultats, pagination et état du complément. Polling borné ou notification à choisir selon l’infrastructure existante ; pas de boucle permanente par frappe.
- Solo et duel doivent accepter les mêmes identités et ignorer les réponses tardives après changement de requête ou de manche.

## Plan d’exécution et livrables

### Étape 1 — Référence reproductible

1. Lire les instructions du dépôt et vérifier les différences depuis l’audit sans recommencer l’investigation entière.
2. Construire un corpus versionné d’au moins 200 requêtes : cas de ce document, préfixes successifs, accents, parenthèses, apostrophes, mots courts, fautes, espaces manquants, artistes homonymes, titres partagés, titre + artiste, collaborations, alphabets réellement représentés.
3. Associer des identifiants attendus et des règles de pertinence explicites. Les SearchMiss ne fournissent pas seuls la bonne réponse. Séparer le corpus de réglage et un jeu de validation conservé à part.
4. Créer des fixtures musicales minimales pour les régressions et un runner de classement réutilisable. Mesurer l’existant sans appels réseau ni mutations distantes.

Livrables : corpus, fixtures, benchmark, baseline datée et distinction entre tests synthétiques et données réelles.

### Étape 2 — Choix du moteur par prototype isolé

1. Comparer Typesense et Meilisearch avec le même modèle, les mêmes données et la même pertinence attendue. Conserver PostgreSQL actuel comme baseline ; tester une variante PostgreSQL ciblée si elle permet de trancher à moindre coût.
2. Utiliser des versions épinglées et une stack de développement séparée de la production. Inspecter les outils disponibles avant de télécharger des dépendances.
3. Prototyper normalisation de recherche complète, poids titre/artiste, typo tolerance, gestion des éditions et titres homonymes.
4. Mesurer qualité, latence chaude/froide, débit, mémoire de pointe, disque, temps d’indexation et coût d’une reconstruction. Un petit échantillon permet une présélection, pas de certifier la capacité sur 3,73 millions de releases.
5. Retenir un moteur avec un court document de décision et un dimensionnement. Ne pas garder plusieurs implémentations complètes en production.

Livrables : prototype, rapport comparatif, choix motivé, besoin éventuel d’hôte séparé. Ce choix technique ne nécessite pas d’approbation supplémentaire pour poursuivre localement.

### Étape 3 — Recherche locale et intégration métier

1. Introduire une interface de recherche et le backend retenu ; conserver l’ancien backend comme repli sous configuration.
2. Implémenter les documents, alias, regroupement sûr et classement. Ne pas modifier silencieusement `answer_matches` pour contourner un problème de résultats.
3. Mettre en place export initial local, synchronisation durable, blocages/suppressions et reconstruction versionnée.
4. Préserver le contrat historique ; ajouter le contrat enrichi si nécessaire, avec tests de compatibilité des anciens clients.

Livrables : recherche locale fonctionnelle, migrations additives éventuelles, indexation reproductible et tests d’intégration PostgreSQL + moteur.

### Étape 4 — Fiabilisation Deezer

1. Introduire une distinction explicite succès/vide/erreur dans le transport et les appelants concernés.
2. Implémenter la machine d’états d’enrichissement et un worker durable avec baux, reprises et déduplication.
3. Remplacer le limiteur fixe par le budget global glissant et priorisé ; vérifier tous les chemins Deezer, pas uniquement la recherche.
4. Définir une transition pour les anciens claims sans statut : ils ne prouvent ni succès ni absence. Revalidation graduelle sous budget, sans purge globale qui déclencherait une rafale.
5. Vérifier crash, concurrence, timeout, code Deezer 4 dans HTTP 200, HTTP 429, panne Redis, annulation utilisateur et absence de résultats.

Livrables : tests déterministes de concurrence/horloge/réseau simulé, métriques et politique de reprise.

### Étape 5 — Mobile et visibilité des erreurs

1. Partager autant que possible la logique de recherche entre solo, duel et choix d’artiste.
2. Préserver debounce et rejet des réponses obsolètes ; intégrer un rafraîchissement borné après enrichissement seulement pour la requête toujours active.
3. Afficher des états distincts : recherche en cours, complément en cours, aucun résultat et indisponibilité temporaire. Les messages restent compréhensibles sans détails internes.
4. Permettre affinage/pagination et sélection d’une réponse même si son édition ne possède pas de preview, sous réserve du contrat de validation retenu.
5. Tester changement de manche, fermeture d’écran, réponse réseau tardive, erreur puis reprise, et compatibilité avec l’API historique.

Livrables : parcours fonctionnels sur les trois écrans et tests mobiles ciblés.

### Étape 6 — Validation et préparation du déploiement

- Exécuter les suites pertinentes de recherche, matching, previews et gameplay ; tests PostgreSQL réels indispensables, SQLite seul ne valide pas index ni plans SQL.
- Mesurer les objectifs ci-dessous sur un environnement isolé représentatif. Ne pas extrapoler un SLA depuis quelques requêtes de production.
- Préparer les configurations, dépendances épinglées, unités de service, migrations, procédure d’import, vérifications et retour arrière. Documenter l’ordre backend compatible → index validé → activation contrôlée → mobile.
- Prévoir métriques : latence p50/p95/p99, absence de résultats, qualité sur corpus, erreurs fournisseur, appels Deezer par type, attente de quota, cache, backlog, ancienneté d’indexation. Aucune réponse secrète ni identifiant personnel en label de métrique.
- Une comparaison en miroir ou une activation progressive en production modifie son fonctionnement : la préparer localement, puis demander l’autorisation.
- S’arrêter avant toute mutation de production et fournir à l’utilisateur le résultat vérifiable, les mesures, les risques restants et la liste exacte des opérations à autoriser.

## Critères d’acceptation proposés

Ces seuils sont des objectifs de conception, pas des performances déjà démontrées.

| Dimension | Critère |
|---|---|
| Régressions explicites | Tous les cas exacts de référence passent ; `q&a` conserve Drake premier ; Simple Minds/Eurythmics deviennent accessibles avec le titre complet |
| Titre + artiste non ambigu | Au moins une édition acceptable dans les cinq premiers résultats pour 100 % des cas annotés de validation |
| Requêtes ambiguës / préfixes / fautes | Recall@20 et rang réciproque moyen améliorés face à la baseline ; aucun cas critique masqué par une moyenne globale ; seuils par catégorie fixés avant le réglage |
| Artistes exacts | Artiste attendu dans les cinq premiers ; ses morceaux prioritaires lorsque la recherche de titres le nomme exactement |
| Latence locale | Cible p95 ≤ 150 ms et p99 ≤ 300 ms côté backend, hors complément Deezer, sur profil de charge documenté et matériel candidat |
| Quota | Au plus 40 appels sortants sur toute fenêtre glissante de cinq secondes, tous consommateurs coordonnés ; tests autour des frontières et en concurrence |
| Reprise | Une panne temporaire ne produit aucun cache négatif de sept jours ; tâche abandonnée récupérable après expiration de son bail |
| Cohérence | Blocages/suppressions propagés ; chaque morceau proposé en manche reste trouvable malgré un retard d’indexation |
| Mobile | Aucun résultat ancien après nouvelle saisie/changement de manche ; complément visible sans retaper ; ancienne API compatible |
| Exploitation | Index reconstructible, synchronisation idempotente, retour arrière documenté ; mémoire de reconstruction mesurée avec marge |

Il n’est pas possible de garantir une couverture du catalogue Deezer complet avec une copie locale partielle, ni une disponibilité externe pendant une panne. L’objectif est de rendre ces limites explicites et de garantir la recherche des données que SongSpot possède et utilise.

## Références de code

- `songspot_backend/game/services/catalog.py` : `_query_filter`, `_candidates`, `_dedupe`, `_search_score`, `_claim`, `_enrich_now`, `_enrich_later`, `search_tracks`, `search_artists`, `bulk_upsert_tracks`, `check_guess`.
- `songspot_backend/game/services/matching.py` : normalisation d’identité et validation des réponses.
- `songspot_backend/game/services/deezer_http.py`, `deezer_service.py`, `cache_utils.py`, `background.py`, `previews.py`.
- `songspot_backend/game/models.py`, `views.py`, `serializers.py`, `consumers.py` et migrations de recherche.
- `songspot_backend/game/tests_open_catalog.py`, `tests_artist_search.py`, `tests_matching.py`, `tests_typos.py`, `tests_deezer_service.py`, `tests_previews.py`.
- `songspot_mobile/lib/providers/game_session_provider.dart`, `screens/duel/duel_game_screen.dart`, `screens/game/style_picker_screen.dart`, `services/api_service.dart`.

## Sources consultées pendant l’audit

- Quota historique par IP : https://stackoverflow.com/a/28278457 ; auteur se présentant comme développeur Deezer : https://stackoverflow.com/users/3790974/fred-dzr.
- Documentation officielle Deezer, redirection vers connexion lors de l’audit : https://developers.deezer.com/api.
- PostgreSQL 16, similarité et index trigrammes : https://www.postgresql.org/docs/16/pgtrgm.html.
- Typesense, pertinence : https://typesense.org/docs/guide/ranking-and-relevance.html ; dimensionnement : https://typesense.org/docs/guide/system-requirements.html.
- Meilisearch, classement : https://www.meilisearch.com/docs/resources/internals/ranking.

Pour implémenter, vérifier la documentation officielle correspondant aux versions effectivement choisies. Aucune estimation de coût ou promesse de mémoire n’est déduite de ces liens seuls.

## Prompt pour une nouvelle conversation

```text
Je veux mettre en œuvre une refonte durable de la recherche SongSpot. Lis d’abord les instructions applicables du dépôt, puis docs/search-redesign-plan.md : il contient l’audit de production du 14 septembre 2026, les bugs reproduits, le plan, les critères d’acceptation et les limites de l’analyse. Vérifie les changements depuis cet audit sans recommencer toute l’investigation.

Exécute ce plan localement jusqu’à obtenir une solution testée et prête à déployer, pas seulement un nouveau plan. Commence par le corpus de non-régression et la baseline, puis compare Typesense et Meilisearch dans un prototype isolé. Choisis le moteur sur les mesures de pertinence, latence et ressources ; conserve PostgreSQL comme alternative si le service supplémentaire n’est pas justifié. Poursuis ensuite avec la recherche, la synchronisation durable, le quota/enrichissement Deezer, la compatibilité API et les trois parcours mobiles. Tiens le document à jour avec les résultats, décisions et étapes terminées. Avance sur les choix techniques raisonnables sans me demander confirmation à chaque étape.

Mon exemple initial était « q&a » de Drake : le dernier correctif le fait déjà remonter premier, cela doit rester vrai. Les titres complets « Don't You (Forget About Me) » de Simple Minds et « Sweet Dreams (Are Made of This) » d’Eurythmics ont été reproduits comme exclus malgré leur présence en base. Il faut corriger les causes générales, pas ajouter des exceptions par chanson. La recherche doit rester cohérente avec les réponses acceptées et les morceaux joués, sans révéler la réponse secrète d’une manche.

Tu as accès à la production par « ssh songspot », exclusivement en lecture seule. Je t’autorise à modifier le dépôt et à développer/tester dans un environnement local isolé. Toute écriture ou action modificatrice en production nécessite mon autorisation explicite préalable, même fichier temporaire, appel GET qui enrichit la base, cache Redis, import, indexation, migration, installation, redémarrage ou déploiement. N’exécute aucun test ni benchmark mutateur contre la production. Prépare entièrement le déploiement et le retour arrière avant de me demander l’autorisation finale.

Dimensionne Deezer pour le plafond historique de 50 requêtes / 5 secondes / IP, avec une cible prudente globale de 40 par fenêtre glissante de cinq secondes, partagée entre previews, recherche et imports. La documentation officielle actuelle n’a pas permis de reconfirmer ce plafond pendant l’audit : garde cette incertitude explicite et ne fais pas de test de saturation en production. Préserve les clients mobiles déjà distribués. À la fin, présente les changements, mesures, tests, limitations et les opérations exactes restant à autoriser pour la production.
```

## Avancement de l'implémentation locale — 14 septembre 2026

Le code initial était toujours au commit audité `2347009` ; seuls ce document
et le fichier `Zone.Identifier` préexistant étaient non suivis. Aucun accès SSH
ni appel HTTP à la production n'a été nécessaire pendant cette implémentation.
Le fichier préexistant n'a pas été modifié.

Réalisé localement :

- Corpus synthétique versionné de 310 requêtes, baseline du commit audité,
  prototypes Typesense 29.0 / Meilisearch 1.15.2, variante PostgreSQL corrigée.
  Jeu complémentaire de 200 requêtes sur 5 363 lignes musicales de la base
  SQLite locale, lue en mode `ro`. Aucun compte, secret ou URL exporté.
- Meilisearch retenu ; interface locale avec repli PostgreSQL, normalisation
  complète, identités stables et regroupement conservateur des éditions.
- Migrations additives 0024 à 0026, backfill borné, outbox transactionnelle par
  triggers PostgreSQL, worker idempotent, reconstruction et bascule atomique,
  contrôle de complétude et conservation de la génération précédente.
- Enrichissement durable avec états, baux, reprise et transition graduelle des
  anciens claims. Le transport direct du worker distingue vide et erreur.
- Quota global glissant dans PostgreSQL, indépendant du Redis évictable,
  réservations prioritaires pour les previews, budget réseau global annulable.
- Crédits invités conservés lorsqu’ils sont fournis, alias du nom actuel de l’artiste.
- API historique préservée et contrat `v=2`, pagination bornée à 400 candidats
  avec affinage, sans utiliser aucune réponse secrète.
- Choix d'artiste, solo et duel : rafraîchissement commun borné, debounce de
  350 ms, rejet des réponses obsolètes, messages distincts FR/EN. Les réponses
  sans preview sont recherchables et restent exclues des manches.
- Tests réels PostgreSQL et Meilisearch : rollback, rejeu, panne d'index,
  retard d'indexation, suppression, blocage et pagination. Tests mobiles ciblés
  et suites complètes. Rapports détaillés et instructions reproductibles dans
  `docs/search/` et `scripts/search_benchmark/README.md`.

Les 310 assertions synthétiques et les 200 assertions titre+artiste réelles
passent. La charge isolée sur 25 282 titres, huit clients et 930 recherches donne
p95 68,65 ms et p99 91,84 ms, reconstruction 5,49 s avec paramètres d'indexation
bornés. Ces mesures ne constituent pas un SLA ni un dimensionnement du catalogue
complet. Voir `docs/search/decision.md` pour les tableaux, ressources, correction
de l'annotation ambiguë `INTRO` et limites des échantillons.

**L'activation du catalogue complet en production n'est pas validée.** Un test
à volume représentatif sur l'hôte candidat et une marge mémoire/disque restent
nécessaires. L'export, l'installation distante, les migrations, la configuration,
les services, l'import/indexation et l'activation exigent toujours l'autorisation
explicite de l'utilisateur. Les fichiers de service, configuration, ordre des
opérations et retour arrière sont préparés dans `docs/search/deployment.md`.
Aucune de ces opérations n'a été exécutée à distance.

Validation finale : **358 tests backend et 96 tests Flutter réussis**, analyse
Flutter et Ruff sans problème, migrations cohérentes. Flutter 3.41.9 / Dart
3.11.5 respecte le verrou existant, qui n’a pas été modifié. Les builds natifs
restent à effectuer sur le MacBook habituellement configuré par l’utilisateur.
Le bilan et les commandes sont dans `docs/search/verification.md`.

## Choix révisé et essais de volume — 15 septembre 2026

L’utilisateur exclut tout achat ou augmentation du VPS. **Le déploiement retenu
utilise PostgreSQL seul, sans Meilisearch.** La comparaison historique des moteurs
reste disponible ; elle ne prescrit plus l’installation d’un service supplémentaire.

Tests locaux : 3 780 448 titres et 778 434 artistes synthétiques/fixtures, CPU et
mémoire limités, puis CPU divisé par deux. Le VPS a seulement été inspecté en
lecture (caractéristiques et statistiques déjà calculées), sans benchmark distant.
Les nouveaux essais ont révélé et permis de corriger les préfixes de deux lettres,
l’index `upper(name)` des artistes, les couples titre + artiste exacts et la
normalisation Unicode SQL. Le backfill crée maintenant huit index requis.

Résultats : 800/800 recherches complètes (dont 500 contrôles générés), 908/1 010
assertions au total ; les saisies partielles et fautes restent un compromis
explicite. À deux recherches/seconde : p95 108,48 ms ; avec CPU réduit : 105,19 ms.
En rafale à huit clients : p95 507,02 ms, sans erreur SQL. Les 364 tests backend
passent. Ces chiffres ne simulent pas à l’identique le processeur ou le disque
du VPS, ni ses autres services.

Voir `docs/search/postgres-scale.md` pour les ressources, limites et rapports,
et `docs/search/deployment.md` pour la livraison PostgreSQL à autoriser.

## Automatisation de la livraison — 15 septembre 2026

Le script de déploiement et GitHub Actions préparent maintenant PostgreSQL seul,
avec sauvegarde préalable, pause des consommateurs, migrations/backfill,
réparation des index invalides, configuration et installation du worker, puis
contrôles avant reprise. Le SHA déployé est celui du workflow ; le checkout actif
n’est plus modifié avant la pause. Les échecs pendant la maintenance laissent
les services arrêtés avec les fichiers de récupération.

Validation : 365 tests backend et 12 tests d’orchestration passent. Le guide de
livraison et la recette Android/iOS/web sont dans `docs/search/deployment.md` et
`docs/search/flutter-checklist.md`. Les 96 tests Flutter de la validation
précédente restent applicables : aucun code Flutter n’a changé pendant cette
préparation du script. Aucun push, merge ou changement de production effectué.
