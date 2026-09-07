# Refonte du catalogue — plan de travail

Contexte : les playlists étaient statiques, le catalogue limité à 206 artistes
seedés, et l'ouverture à Deezer a introduit des appels live sur le chemin des
requêtes. Ce document trace ce qui change, pourquoi, et comment le tester.

## Le fait qui structure tout

Mesuré le 2026-09-06 sur l'API publique Deezer :

```
https://cdnt-preview.dzcdn.net/api/1/1/6/a/2/0/<hash>.mp3
  ?hdnea=exp=1788690859~acl=...~hmac=...
```

`exp` est **systématiquement à +15,0 minutes**, sur tous les endpoints testés
(`/track`, `/artist/{id}/top`, `/album/{id}/tracks`, `/chart`, `/search`).

Trois conséquences, qui sont l'ossature de ce plan :

1. **Une `preview_url` stockée en base est morte au bout de 15 minutes.** Ce
   n'était pas un bug de peuplement, c'est structurel. On ne la stocke plus.
2. **Il n'existe pas d'endpoint batch par IDs** (`/tracks?ids=...` → erreur
   600). Une preview isolée coûte un appel entier.
3. **Mais les endpoints « conteneur » rendent 100 previews signées par appel**
   (`/playlist/{id}/tracks`, `/chart/0/tracks`, `/artist/{id}/top`), et le
   token n'est lié ni au joueur ni à l'IP (`user_id=0, application_id=42`).
   Donc **un appel sert tous les joueurs simultanés du même pool.**

Le point (3) est le levier central : le nombre d'appels dépend du **nombre de
pools distincts et du temps**, pas du nombre d'utilisateurs. À 3 000 DAU comme
à 30 000, le mode catégorie coûte le même prix.

## Principe directeur

Séparer deux choses que le code confond aujourd'hui :

| | Durée de vie | Où | Alimenté par |
|---|---|---|---|
| **Métadonnées** (titre, artiste, deezer_id, rank, cover) | permanent | Postgres | ETL nocturne + à la demande |
| **Preview URL** | **15 min** | Redis seulement | juste-à-temps, par conteneur |

Et une règle : **Deezer est une dépendance d'ETL, jamais une dépendance de
requête.** Aucun appel Deezer ne doit se trouver sur un chemin où un joueur
attend.

## Budget cible

Capacité : 40 appels / 5 s = 8/s ≈ 690 000/jour.

| Poste | Appels/jour |
|---|---|
| Pools de catégories (15 × 6/h × 24 h) | ~2 200 |
| Pools d'artistes | ~4 000 (à mesurer, cf. requête plus bas) |
| Enrichissement autocomplete (plafonné) | ~5 000 |
| ETL nocturne | ~20 000 |
| **Total** | **~31 000 (4,5 %)** |

---

# Phases

## P0 — Previews juste-à-temps par conteneur

**Le problème corrigé** : aujourd'hui on sert des `preview_url` lues en base.
Passé 15 minutes après leur import, elles renvoient 403. C'est un bug de prod
actif, pas seulement une dette.

**Ce qui change**

- Nouveau `game/services/previews.py` : un « pool » = la réponse d'un endpoint
  conteneur, mise en cache Redis **10 minutes** (marge de 5 min sur les 15 du
  token). Clé par conteneur, donc partagée entre tous les joueurs.
- **`preview_url` est supprimée de la base**, remplacée par un booléen
  `has_preview`. J'avais d'abord voulu la garder comme repli de panne ; c'était
  une erreur, relevée à la relecture : toute ligne vieille de plus d'un quart
  d'heure porte une URL expirée, donc ce repli n'aurait pratiquement jamais
  fonctionné tout en coûtant 266 octets sur chaque ligne. Une panne Deezer
  renvoie maintenant un 503 honnête plutôt qu'un audio silencieusement cassé.
- **`playable()` exige désormais un `deezer_id`.** C'est le seul identifiant
  dont dispose le résolveur : une ligne sans lui ne peut produire aucun audio
  et n'aurait fait que générer des 503. Les lignes héritées sans ID sortent
  donc du pool jusqu'à ce qu'un ré-import leur en attribue un.
- `refresh_preview_urls` est **supprimée**. Elle parcourait toutes les pistes
  pour stocker une URL par appel : avec des jetons de 15 minutes, elle brûlait
  le quota pour écrire des données mortes avant même la fin de la commande.
- `NextSongView` : après avoir choisi une piste, résout sa preview via le pool.
  Si le pool ne la contient pas, repli sur un `/track/{id}` unitaire.
- Le client reçoit **une URL par manche**, jamais un lot en début de session :
  au round 15 un lot serait périmé.

**Pourquoi 10 minutes et pas 14** : la piste servie doit avoir assez de vie
restante pour être préchargée puis jouée. À 10 min de cache, la pire URL servie
a encore 5 minutes devant elle.

## P1 — Autocomplete local d'abord

**Le problème corrigé** : `catalog.search_tracks()` appelle Deezer *puis*
exécute `upsert_tracks()` (50 pistes × ~2 requêtes SQL) **avant** de répondre,
et ce même quand la réponse Deezer vient du cache. C'est ~100 requêtes SQL
séquentielles par frappe débouncée. C'est la latence que les joueurs
ressentent, bien plus que Deezer.

**Ce qui change**

- La recherche répond **immédiatement depuis Postgres**.
- L'enrichissement Deezer part en tâche de fond : un pool de threads **dans le
  processus Django existant**. Aucun démon, rien à installer, rien à lancer.
  Pas de Celery — ce serait un broker, un worker, une unit systemd et un
  changement de déploiement pour un travail dont le seul mode d'échec est « le
  catalogue apprend cette chanson un peu plus tard ». L'interface est celle
  qu'aurait Celery, pour pouvoir basculer plus tard sans toucher au reste.
- Piloté par `BACKGROUND_TASKS_ENABLED`, **désactivé en local et sous test**
  (défaut : `not DEBUG`). Rien ne tourne en fond sur une machine de dev.
- Déduplication par requête normalisée (flag Redis 7 jours) : « despacito » est
  enrichi une fois par semaine, pas 400 fois par jour.
- Ne s'enclenche que si le local a rendu peu de résultats.
- File plafonnée : au-delà, on jette. Une recherche non enrichie n'est pas une
  erreur, juste une occasion manquée.
- Les upserts passent en `bulk_create(ignore_conflicts=True)`.

## P2 — Index

- `pg_trgm` + index GIN sur `norm_title` / `norm_artist`. Sans ça, P1 s'effondre
  dès que le catalogue grossit : `_query_filter` génère des `LIKE '%token%'`
  qu'aucun index B-tree ne peut servir (joker à gauche) → seq scan complet.
- Suppression des index redondants : `title` et `artist` en B-tree ne peuvent
  pas servir un `LIKE '%x%'`, et `is_curated` sur un booléen n'a presque aucune
  sélectivité.
- Migration conditionnelle : PostgreSQL uniquement, SQLite en dev l'ignore.

## P3 — Colonne `is_variant`

**Le problème corrigé** : `is_variant_title()` n'est appliqué qu'à l'import,
dans `is_playable_payload()`, et il est court-circuité quand `directed=True`.
Or `playable()` ne filtre pas les variantes à la lecture. Donc un
« Blinding Lights (Live) » importé pendant une session dirigée sur The Weeknd
atterrit en base, puis peut être servi dans une manche « toutes catégories » —
d'autant plus facilement que les pistes issues des albums ont souvent `rank=0`,
qui passe le plancher de popularité.

**Ce qui change** : colonne `is_variant` posée à l'import, filtrée dans
`playable(directed=False)`. Les variantes restent en base — un live est une
*bonne réponse* — mais ne sont plus jamais jouées ni proposées en premier.

## P4 — Tirage aléatoire

`NextSongView` fait `qs.count()` puis `qs[random.randint(...)]`, soit un
`OFFSET` aléatoire. Correct sur 4 000 lignes, désastreux sur 1 million.
Remplacé par un tirage sur une liste d'IDs bornée.

## P5 — Crawl du graphe d'artistes (ETL)

`refresh_catalog` couvre les charts et playlists éditoriales. Il lui manque la
couverture du long tail, qui est ce qui génère les remarques sur les stores.

- Nouvelle commande `crawl_artists` : parcours en largeur via
  `/artist/{id}/related` (20 artistes/appel), puis `/artist/{id}/top` pour
  chacun.
- Métadonnées uniquement, jamais de previews.
- Plafonnée en nombre d'appels, reprenable, tourne la nuit à 8 appels/s.
- Amorcée par les têtes de charts et par les **recherches sans résultat**
  loggées par P1 — c'est la liste de priorités la plus directe qui soit.

## P6 — Dénormaliser `artist_picture_url`

`artist_picture_url` faisait 103 caractères en moyenne, répété sur chaque piste
du même artiste, alors que `Artist.picture_url` tient la même valeur depuis
l'ouverture du catalogue. Migration 0016 : créer les fiches `artists`
manquantes depuis les pistes, y recopier les photos, puis supprimer la colonne.

Deux choses découvertes en le faisant, toutes deux réglées :

* **1 134 pistes n'avaient aucun `deezer_artist_id`** (307 artistes), donc
  aucune fiche possible — `artists` est clé sur cet identifiant. Sans rien
  faire, 170 d'entre eux auraient perdu leur avatar dans l'écran de sélection.
  Nouvelle commande `link_legacy_artists` : elle résout chaque nom une fois par
  identifiant Deezer et **refuse toute correspondance dont le nom normalisé
  diffère** — accepter le premier résultat aurait attribué la mauvaise identité
  à des discographies entières, silencieusement. Résultat sur la base de dev :
  307/307 résolus, 0 piste sans identifiant d'artiste.
* **Un bug de suppression d'enrichissement.** `_local_artists` renvoie des
  fiches de substitution construites depuis un nom de piste ; elles comptaient
  comme de la couverture, donc une recherche qui ne renvoyait que des
  substituts ne déclenchait jamais l'enrichissement et l'artiste ne pouvait
  jamais devenir une vraie entité Deezer. Seules les fiches ayant un
  `deezer_id` comptent désormais.

Le repli par nom reste en place pour les actes que Deezer ne connaît pas : ils
restent cherchables et jouables, simplement sans photo.

---

# Stockage attendu

Moyennes mesurées sur les lignes réelles : `preview_url` 266 car. (la moitié de
la ligne, pour une donnée morte en 15 min), `cover_url` 102, 
`artist_picture_url` 103, le reste 49.

Texte moyen par ligne, mesuré sur les mêmes données : **519,6 → 246,5
caractères**, soit **-53 %**, en retirant `preview_url`.

| | Avant | Maintenant | Après dénormalisation |
|---|---|---|---|
| Ligne (heap) | ~380 o | ~265 o | ~165 o |
| Index | ~350 o | ~285 o | ~235 o |
| **Total/piste** | **~730 o** | **~550 o** | **~400 o** |

Soit **~550 Mo pour 1 M de pistes** aujourd'hui. Le reste attend le
déplacement d'`artist_picture_url` vers la table `artists`, où il a déjà sa
place.

Soit **~500 Mo pour 1 M de pistes**, ~1,5 Go pour 3 M. Le stockage n'est pas
une contrainte ; le temps de crawl l'est.

---

# Comment tester

Chaque phase se vérifie indépendamment : commandes et résultats attendus dans
**`docs/catalogue-tests.md`**.

## Impact client

Le contrat de l'API ne change pas : `preview_url` garde son nom et sa forme.
Une seule chose est nouvelle — `/next-song/` et `/tracks/<id>/refresh-preview/`
peuvent répondre **503 `AUDIO_UNAVAILABLE`** quand Deezer est injoignable.
Distinct du 404, qui signifie « vous avez tout écouté » et termine la session.

Traité côté application : `api_service.dart` traduit le code en
`backendAudioUnavailable` (EN + FR), affiché sur l'écran d'erreur qui porte
déjà un bouton « Réessayer ». Aucune allowlist CSP web, exception ATS iOS ou
`network_security_config` Android ne référence de domaine Deezer, donc le
changement de host CDN (`cdns-preview-*` → `cdnt-preview.dzcdn.net`) ne
demande rien.

## État

| Phase | Statut |
|---|---|
| P0 previews juste-à-temps | fait |
| P1 autocomplete local d'abord | fait |
| P2 index trigrammes | fait (actif en PostgreSQL seulement) |
| P3 colonne `is_variant` | fait |
| P4 tirage aléatoire | fait |
| P5 crawl du graphe d'artistes | fait |
| P6 `has_preview` | fait |
| P6 dénormalisation `artist_picture_url` | fait |

Rendement mesuré du crawl : **15 appels → 8 artistes → 381 pistes**, soit ~25
pistes par appel. Une nuit à 20 000 appels ≈ 10 000 artistes / 500 000 pistes.

Requête à passer en prod pour calibrer le budget « pools d'artistes » :

```sql
SELECT round(sum(nb) / 30.0) AS appels_artistes_par_jour
FROM (
  SELECT date_trunc('hour', played_at)
           + interval '10 min' * floor(extract(minute FROM played_at) / 10) AS fenetre,
         count(DISTINCT artist_filter) AS nb
  FROM game_scores
  WHERE played_at > now() - interval '30 days'
    AND artist_filter <> ''
  GROUP BY 1
) w;
```
