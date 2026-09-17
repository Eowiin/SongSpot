# PostgreSQL sur le VPS existant — tests du 15 septembre 2026

**Conclusion : poursuivre avec PostgreSQL seul, sans achat ni Meilisearch.**
Les recherches complètes passent et le débit proche du pic observé reste peu
coûteux dans la simulation. Les mesures ne certifient pas les temps de réponse
sur le VPS réel ni sa capacité avec de futurs projets supplémentaires.

## Périmètre et limites

- 3 780 448 titres et 778 434 artistes dans PostgreSQL 16 local : volume proche
  des estimations récentes de production, pas un export de sa base.
- Quotas : PostgreSQL 2 CPU / 3 Gio sans swap ; backend 1 CPU / 512 Mio. Un second
  scénario réduit le CPU à 1 pour PostgreSQL et 0,5 pour le backend.
- Réglages PostgreSQL relevés en lecture seule sur le VPS : `shared_buffers=1GB`,
  `work_mem=4MB`, `effective_cache_size=2500MB`, deux workers parallèles par gather.
- Le processeur local est un Ryzen 7 9800X3D ; le VPS expose quatre vCPU EPYC-Rome.
  **Un quota CPU ne reproduit pas le modèle du processeur**, son partage chez
  l’hébergeur ou les performances du stockage. Aucun test CPU/disque distant.
- L’audit montrait un pic de 94 recherches sur une minute. Le scénario à deux
  recherches/seconde dépasse légèrement ce débit moyen sur une minute ; il ne
  reproduit pas les rafales réelles ni le mélange exact des requêtes.
- Appels directs au service de recherche, avec mise en file durable des
  compléments, sans HTTP/mobile, worker fournisseur ni appel Deezer. Les autres
  applications, Redis, les imports et les previews ne sont pas chargés en parallèle.
- Les documents synthétiques sont plus compacts que ceux de production : table
  `tracks` locale d’environ 814 Mio, contre 1 089 Mio dans le relevé distant avant
  ajout des champs de recherche. Le nombre de lignes seul n’égale pas les
  distributions, la taille ou la diversité des données réelles.

Les commandes SSH ont uniquement lu les caractéristiques système, réglages,
statistiques existantes et tailles de tables. Aucun fichier distant, donnée,
cache ou service de production n’a été modifié. Le relevé est conservé dans
[vps-readonly-2026-09-14.json](vps-readonly-2026-09-14.json).

## Résultats de performance

Le p95 ci-dessous inclut l’attente dans la file locale pour les tests à débit
imposé. Les temps réseau, l’authentification HTTP et le debounce mobile sont exclus.

| Scénario | Requêtes | p95 | p99 du traitement | Erreurs SQL |
|---|---:|---:|---:|---:|
| 2 recherches/s, 2 CPU DB + 1 CPU backend, 82 s | 165 | 108,48 ms | 141,21 ms | 0 |
| Même débit, 1 CPU DB + 0,5 CPU backend, 82 s | 165 | 105,19 ms | 206,87 ms | 0 |
| 8 clients en continu, 660 recherches en 12,68 s | 660 | 507,02 ms | 698,42 ms | 0 |
| Corpus complet, un client, après échauffement | 1 034 | 31,39 ms | 58,53 ms | 0 |
| Même corpus après redémarrage de PostgreSQL | 1 034 | 58,75 ms | 197,41 ms | 0 |

La rafale atteint environ 52 recherches/s et occupe les deux CPU autorisés à
PostgreSQL. Ce débit est celui du mélange synthétique, pas une capacité garantie.
Le corpus complet comporte davantage de requêtes précises que le mélange de
charge : ne pas comparer directement leurs percentiles. Le redémarrage vide les
buffers PostgreSQL, **pas le cache disque du système hôte**. Les durées restent
courtes : il ne s’agit pas d’un test d’endurance de plusieurs heures.

Rapports : [débit normal](postgres-3780k-2rps.json),
[CPU réduit](postgres-3780k-halfcpu-2rps.json), [rafale](postgres-3780k-burst.json),
[corpus complet](postgres-3780k-quality.json), [redémarrage](postgres-3780k-restart.json).

## CPU, mémoire et disque

À deux recherches/seconde, les compteurs indiquent en moyenne **0,068 cœur local
pour PostgreSQL et 0,015 pour le backend** : environ 0,083 cœur au total sur ce
processeur. En rafale, PostgreSQL atteint son quota de deux cœurs. Ces unités ne
sont pas un pourcentage CPU prédit sur le VPS.

Après correction, les maxima de mémoire échantillonnés vont d’environ **1,19 à
1,76 Gio pour PostgreSQL**, cache de fichiers et mémoire partagée compris ; le
processus de test backend reste sous 100 Mio. La construction du catalogue a
atteint la limite de 3 Gio. Aucun OOM n’est enregistré. Ce sont les ressources de
l’ensemble de PostgreSQL isolé, pas un supplément à ajouter à sa mémoire actuelle
sur le VPS. Le worker applicatif et les autres services ne sont pas inclus.

La base synthétique occupe **3,23 Gio**, dont **726 Mio pour les huit nouveaux
index de recherche**. Les trois index ajoutés à la suite des essais de volume
représentent environ 341 Mio de ce total. Ces tailles excluent le WAL, les
sauvegardes et les fichiers temporaires de construction. Prévoir aussi les champs
textuels ajoutés aux lignes ; les tailles exactes dépendront du catalogue réel.
L’[inventaire SQL](postgres-3780k-storage.json) détaille les index.

Le VPS disposait d’environ 48,7 Gio de disque et 3,6 Gio de RAM disponibles lors
du relevé. La simulation apporte des éléments favorables à la cohabitation,
mais les futurs projets et les imports peuvent consommer cette marge.

## Corrections révélées par le volume

Avant correction, `li` atteignait le délai SQL de 2,5 secondes. Le plan relisait
plus de deux millions de lignes à cause d’un bitmap trigramme imprécis et du
`work_mem` de 4 Mio. Deux index sur le préfixe de deux caractères, le rang et
l’UUID permettent maintenant deux lectures ordonnées limitées à 200 lignes,
puis le classement commun. Le service traite `li` en environ 16 ms lors du
passage chaud. Les plans vérifient l’usage des index dédiés.

Un index sur `upper(artists.name)` corrige aussi un parcours complet de la table
artistes : l’ancien index portait sur `name`, alors que Django interroge `upper(name)`.
Les couples titre + artiste exacts entrent désormais dans les candidats avant
les sous-chaînes populaires. La normalisation SQL NFKD conserve la recherche
sur les titres coréens, comme la normalisation Python existante.

Les plans [avant](postgres-3780k-plans-before.json) et
[après](postgres-3780k-plans-after.json) sont conservés. Les timings avant/après
ne garantissent pas des caches identiques ; les changements de plans expliquent
le gain au-delà de l’échauffement.

## Qualité : résultats et compromis explicites

| Assertions sur le catalogue étendu | Réussites |
|---|---:|
| Titres exacts | 50/50 |
| Titres + artistes du corpus musical | 250/250 |
| Titres + artistes générés, répartis dans tout le catalogue | 500/500 |
| Préfixes | 48/100 |
| Espaces manquants | 24/50 |
| Requêtes nom d’artiste, avec chansons attendues imposées | 29/50 |
| Régressions diverses, dont fautes | 7/10 |
| Total des assertions strictes | 908/1 010 |

`q&a` reste premier. Les titres complets de Simple Minds et Eurythmics sont
retrouvés. **Les 102 autres assertions ne sont pas présentées comme réussies.**
Les attentes imposant une chanson précise à partir d’un nom d’artiste ou d’un
préfixe deviennent plus restrictives avec l’ajout d’autres chansons ; elles ne
mesurent pas à elles seules la pertinence musicale de tous les résultats.
Les fautes et espaces manquants restent une faiblesse réelle du mode PostgreSQL.
Aucun complément Deezer n’a été exécuté pour masquer ces limites dans le test.

Les 500 nouveaux contrôles sont calculés directement depuis la formule du
catalogue généré, sans prélecture des lignes ciblées. Ce sont des contrôles de
couverture et de performance, pas 500 requêtes humaines indépendantes. Le README
décrit aussi la densité synthétique des éditions et les différences avec les
premiers paliers 100k/1m : ces derniers ne forment pas une courbe contrôlée du jeu final.

## Validation et livraison

- 364 tests backend complets réussis sur PostgreSQL ; Ruff sans erreur.
- Migrations cohérentes ; huit index valides ; champs complets ; outbox vide.
- 106 tâches synthétiques restent `pending` après les mesures : aucun worker
  fournisseur n’a été lancé. Elles appartiennent uniquement à la base de test.
- Le worker peut fonctionner sans moteur externe et respecte la désactivation
  des compléments. Une activation future d’un moteur imposerait une reconstruction.
- Le mobile n’a pas changé pendant ces essais : ses 96 tests du précédent passage
  restent consignés ; les builds natifs restent à faire sur le MacBook.

La [procédure de livraison](deployment.md) vise maintenant PostgreSQL seul.
Aucun achat, installation Meilisearch ou changement de production n’a été effectué.
Les conteneurs locaux peuvent être arrêtés en conservant leur volume pour reproduction.
