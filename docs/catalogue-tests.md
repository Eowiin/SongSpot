# Vérifier la refonte du catalogue

Chaque section se teste indépendamment. Les commandes se lancent depuis
`songspot_backend/`, avec `.venv/bin/python`.

Suite complète d'abord :

```bash
.venv/bin/python manage.py test game
# 185 tests, OK
```

---

## P0 — Previews juste-à-temps

### 1. Confirmer soi-même la fenêtre de 15 minutes

C'est le fait sur lequel repose toute l'architecture ; il vaut la peine de le
revérifier de temps en temps, Deezer pouvant la changer.

```bash
.venv/bin/python - <<'EOF'
import json, re, time, urllib.request
d = json.load(urllib.request.urlopen('https://api.deezer.com/track/3135556'))
exp = int(re.search(r'exp=(\d+)', d['preview']).group(1))
print('TTL du token :', round((exp - time.time()) / 60, 1), 'min')
EOF
```

**Attendu** : `15.0 min`. Si ce chiffre change, ajuster `POOL_TTL` dans
`game/services/previews.py` en gardant 5 minutes de marge.

### 2. Un appel sert tout le monde

C'est la propriété qui découple les appels du nombre de joueurs.

```bash
.venv/bin/python - <<'EOF'
import os, django, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'songspot.settings')
django.setup()
from game.services import previews
t0 = time.time(); a = previews.container_previews('artist', 27); t1 = time.time()
b = previews.container_previews('artist', 27); t2 = time.time()
print(f'1er appel : {len(a)} previews en {t1-t0:.2f}s')
print(f'2e appel  : {len(b)} previews en {t2-t1:.4f}s')
EOF
```

**Attendu** : 100 previews au premier appel, 100 au second en ~0,0000 s. Le
second ne doit produire **aucun** trafic réseau.

### 3. Une manche renvoie de l'audio qui joue vraiment

```bash
.venv/bin/python - <<'EOF'
import os, django, re, time, urllib.request
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'songspot.settings')
django.setup()
from django.test import Client
from game.models import Track
r = Client().get('/api/game/next-song/', {'v': 2})
url = r.json()['preview_url']
exp = re.search(r'exp=(\d+)', url)
print('TTL restant :', f"{(int(exp.group(1))-time.time())/60:.1f} min" if exp else 'NON SIGNÉE (repli base)')
req = urllib.request.Request(url, headers={'Range': 'bytes=0-1023'})
print('audio :', urllib.request.urlopen(req, timeout=15).status)
print('colonne preview_url :', hasattr(Track.objects.first(), 'preview_url'))
EOF
```

**Attendu** : TTL ≈ 15 min, `audio : 206`, et `colonne preview_url : False` —
la table ne porte plus qu'un booléen `has_preview`, l'URL n'existe qu'en
mémoire le temps de la réponse.

### 3 bis. Une panne Deezer donne un 503, pas un 404

```bash
.venv/bin/python manage.py shell -c "
from unittest.mock import patch
from django.test import Client
with patch('game.views.previews.resolve', return_value=None):
    print('status :', Client().get('/api/game/next-song/', {'v': 2}).status_code)
"
```

**Attendu** : `503`, avec `error_code: "AUDIO_UNAVAILABLE"` dans le corps. Un
404 dirait au joueur que le catalogue est vide, ce qui l'envoie désinstaller
l'application ; un 503 lui dit de réessayer.

Côté application, ce code est traduit (`api_service.dart` →
`backendAudioUnavailable`) et s'affiche sur l'écran d'erreur, qui porte déjà un
bouton « Réessayer ». La session **ne se termine pas** : seul le 404 la
termine. À vérifier à la main en coupant le réseau du serveur pendant une
partie.

### 4. Mesurer le coût réel en production

Une fois déployé, sur quelques heures :

```bash
journalctl -u songspot --since '-6h' | grep -c 'Deezer refused'   # doit rester ~0
redis-cli --scan --pattern 'songspot:*preview:pool:*' | wc -l     # pools chauds
```

Si `Deezer refused` grimpe, c'est que `POOL_TTL` est trop court ou que Redis
n'est pas partagé entre workers — vérifier `CACHE_REDIS_URL`.

---

## P1 — Autocomplete local d'abord

> **Rien ne tourne en fond en local.** L'enrichissement est piloté par
> `BACKGROUND_TASKS_ENABLED`, dont le défaut est `not DEBUG` — donc désactivé
> en développement et sous test. Aucun thread n'est démarré, aucun appel
> Deezer ne part derrière votre dos. Pour l'essayer quand même :
> `BACKGROUND_TASKS_ENABLED=True` dans l'environnement.
>
> Ce n'est pas Celery : c'est un pool de threads dans le processus Django déjà
> en cours. Il n'y a aucun démon à installer ni à lancer, en local comme en
> prod.

### 1. Une requête connue ne touche plus Deezer

```bash
.venv/bin/python - <<'EOF'
import os, django, time
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'songspot.settings')
django.setup()
from game.services import catalog
for q in ['blinding', 'daft', 'stromae']:
    t = time.time(); n = len(catalog.search_tracks(q)); print(f'{q:12} {n:2} résultats  {time.time()-t:.3f}s')
EOF
```

**Attendu** : quelques millisecondes par requête dès que le catalogue les
couvre. Avant ce changement, chaque frappe payait un aller-retour Deezer plus
~100 requêtes SQL.

### 2. Une requête inconnue est enrichie une seule fois

```bash
.venv/bin/python manage.py shell -c "
from unittest.mock import patch
from game.services import catalog
with patch('game.services.catalog.DeezerService') as d:
    d.return_value.search_track.return_value = {'data': []}
    for _ in range(3): catalog.search_tracks('un truc introuvable')
    print('appels Deezer :', d.return_value.search_track.call_count)
"
```

**Attendu** : `1`. Le verrou Redis tient 7 jours.

### 3. Les recherches infructueuses alimentent le crawler

```bash
.venv/bin/python manage.py shell -c "
from game.models import SearchMiss
for m in SearchMiss.objects.order_by('-hits')[:15]:
    print(f'{m.hits:4}  {m.query}')
"
```

C'est la liste à surveiller après le déploiement : elle dit exactement ce qui
manque au catalogue, artiste par artiste.

---

## P2 — Index trigrammes (PostgreSQL uniquement)

En dev sur SQLite la migration ne fait rien, c'est normal. En prod :

```bash
psql "$DATABASE_URL" -c "\di+ tracks*"
```

**Attendu** : `tracks_title_trgm`, `tracks_artist_trgm`,
`tracks_norm_title_trgm`, `tracks_norm_artist_trgm` en `gin`, et l'absence de
`tracks_title_f94b39_idx` / `tracks_artist_707385_idx`.

Vérifier que le planificateur les utilise vraiment :

```bash
psql "$DATABASE_URL" -c "
EXPLAIN ANALYZE
SELECT * FROM tracks
WHERE norm_title LIKE '%blinding%' OR norm_artist LIKE '%blinding%'
   OR title ILIKE '%blinding%' OR artist ILIKE '%blinding%'
ORDER BY rank DESC LIMIT 150;"
```

**Attendu** : `Bitmap Heap Scan` avec plusieurs `Bitmap Index Scan on
tracks_*_trgm`. Si vous voyez `Seq Scan`, c'est qu'une des quatre colonnes n'a
pas son index — PostgreSQL ne peut pas faire de OR bitmap partiel.

---

## P3 — Variantes jamais jouées

```bash
.venv/bin/python manage.py shell -c "
from game.models import Track
from game.services import catalog
tot = Track.objects.count()
var = Track.objects.filter(is_variant=True).count()
print(f'{var} variantes sur {tot} pistes')
print('variantes jouables en non dirigé :',
      catalog.playable(Track.objects.all(), directed=False).filter(is_variant=True).count())
print('variantes jouables en dirigé     :',
      catalog.playable(Track.objects.all(), directed=True).filter(is_variant=True).count())
"
```

**Attendu** : 0 en non dirigé, > 0 en dirigé. Une variante reste une bonne
réponse — seulement jamais une manche quand c'est le jeu qui choisit.

---

## P4 — Tirage aléatoire

```bash
.venv/bin/python manage.py shell -c "
import time
from game.models import Track
from game.views import _random_candidates
from game.services import catalog
qs = catalog.playable(Track.objects.all(), directed=False)
t = time.time()
ids = {t_.id for _ in range(20) for t_ in _random_candidates(qs, 3)}
print(f'{len(ids)} pistes distinctes sur 60 tirages en {time.time()-t:.3f}s')
"
```

**Attendu** : une bonne dispersion (proche de 60 distinctes sur un gros
catalogue) et un temps stable quand la table grossit. L'ancien code faisait un
`COUNT` plus un `OFFSET` aléatoire, dont le coût croît linéairement.

---

## P5 — Crawl du graphe d'artistes

Commencer petit pour mesurer le rendement :

```bash
.venv/bin/python manage.py crawl_artists --max-calls 15 --seeds-only charts
```

**Mesuré ici** : 15 appels → 8 artistes → 381 pistes, frontière passée de 235 à
278 artistes en attente. Soit **~25 pistes par appel**.

Extrapolation pour une nuit à 20 000 appels : ~10 000 artistes et ~500 000
pistes. À ~500 o la ligne, ~250 Mo.

À blanc, pour voir les graines sans rien écrire :

```bash
.venv/bin/python manage.py crawl_artists --dry-run
```

En priorité sur ce que les joueurs ont cherché sans succès :

```bash
.venv/bin/python manage.py crawl_artists --seeds-only misses --max-calls 2000
```

Suivi de la croissance :

```bash
.venv/bin/python manage.py shell -c "
from game.models import Artist, Track
print('artistes :', Artist.objects.count())
print('pistes   :', Track.objects.count())
print('artistes stockés :', Artist.objects.filter(top_refreshed_at__isnull=False).count())
"
```

---

## P6 — Artwork sur `artists`

```bash
.venv/bin/python manage.py shell -c "
from game.models import Track, Artist
print('pistes sans deezer_artist_id :', Track.objects.filter(deezer_artist_id__isnull=True).count())
print('fiches artistes :', Artist.objects.count())
print('  avec photo    :', Artist.objects.exclude(picture_url__isnull=True).exclude(picture_url='').count())
print('colonne artist_picture_url :', hasattr(Track.objects.first(), 'artist_picture_url'))
"
```

**Attendu** : `colonne artist_picture_url : False`, et un nombre de pistes sans
`deezer_artist_id` proche de zéro **après** avoir passé :

```bash
.venv/bin/python manage.py link_legacy_artists --dry-run   # voir d'abord
.venv/bin/python manage.py link_legacy_artists
```

**Mesuré en dev** : 307 noms résolus, 307 acceptés, 0 refusé, 1 134 pistes
rattachées. Un nom refusé n'est pas une erreur — l'artiste continue de
fonctionner par nom, simplement sans photo ni session dirigée.

Vérifier que le garde-fou anti-homonyme fonctionne :

```bash
.venv/bin/python manage.py shell -c "
from unittest.mock import patch
from game.services import catalog
with patch('game.services.catalog.DeezerService') as d:
    d.return_value.search_artists.return_value = [{'id': 1, 'name': 'The Retro Weeknd', 'nb_fan': 64}]
    print('correspondance approximative :', catalog.resolve_artist('The Weeknd'))
"
```

**Attendu** : `None`. Accepter ce résultat aurait collé « The Retro Weeknd »,
un groupe de reprises, sur toute la discographie de The Weeknd.

---

## Déploiement

```bash
sudo cp scripts/systemd/songspot-crawl-artists.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now songspot-crawl-artists.timer
systemctl list-timers 'songspot-*'
```

Le crawl tourne à 05h30, une heure après `refresh_catalog`, pour que les deux
ne se disputent jamais le quota Deezer.

## Calibrer le budget « pools d'artistes » sur les vraies données

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
