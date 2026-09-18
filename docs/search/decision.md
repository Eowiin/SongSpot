# Comparaison des moteurs — 14 septembre 2026

> **Choix de livraison révisé : PostgreSQL seul**, conformément au budget fixé
> par l’utilisateur. Les mesures ci-dessous restent celles de la comparaison
> initiale ; Meilisearch est une option non déployée. Voir [deployment.md](deployment.md)
> et les nouveaux essais de volume dans [postgres-scale.md](postgres-scale.md).

Choix : **Meilisearch 1.15.2**, recherche PostgreSQL complète en repli. Les
versions et empreintes Docker figurent dans `scripts/search_benchmark/compose.yml`.
Le backend conserve `SEARCH_BACKEND=legacy` par défaut jusqu'à validation de
l'index. Le code de validation des réponses n'a pas été modifié.

## Résultats reproductibles

Les fichiers JSON voisins contiennent chaque requête, identifiants de fixture
attendus, rang obtenu, temps et assertion. Les identifiants du corpus synthétique
ne sont pas des identifiants Deezer réels.

| Jeu de validation | Existant (commit 2347009) | Typesense 29.0 | Meilisearch 1.15.2 | Intégration retenue |
|---|---:|---:|---:|---:|
| Synthétique, Recall@20, 88 requêtes | 87,5 % | 98,86 % | 100 % | 100 % |
| Synthétique, MRR | 0,875 | 0,946 | 0,969 | 0,957 |
| Réel local, titre+artiste dans le top 5, 200 requêtes | 185/200 | 200/200 | 200/200 | 200/200 |
| Réel local, MRR | 0,922 | 1,000 | 0,998 | 0,998 |
| Réel local, p95, premier passage | 4,83 ms | 1,72 ms | 2,09 ms | 10,10 ms |

L'intégration passe les **310 assertions synthétiques**, dont q&a/Drake premier,
les titres complets parenthétiques, les fautes et espaces manquants. Les 200
requêtes réelles ont été définies après le réglage synthétique, sans être utilisées
pour ajuster les poids. Elles proviennent de 5 363 lignes musicales de la base
SQLite locale préexistante. Ce n'est pas un échantillon de production.

La variante PostgreSQL avec champs complets et classement lexical atteint
92,05 % de Recall@20 sur la validation synthétique, contre 100 % avec le moteur.
Le service supplémentaire apporte ici les fautes et les espaces manquants.
Typesense est plus léger et légèrement plus rapide dans le prototype. Meilisearch
retrouve `motion` avec le modèle commun sans suppression de mots et a le meilleur
rappel synthétique ; ce gain motive sa sélection. Les différences de MRR entre
le moteur brut et l'intégration viennent du classement lexical explicite et du
repli SQL, pas d'un bonus utilisant une réponse secrète.

Une annotation initiale imposait un top 5 pour `INTRO` seul. Le corpus v2 corrige
ce critère à top 20, conformément au plan. `intro damso` reste top 5. Les rapports
initiaux sont conservés avec leurs assertions originales ; leurs métriques de
rang ne changent pas. Voir le README du benchmark.

## Charge et ressources

Environnement : Docker local Linux/WSL, limite mémoire visible 15,21 Gio,
PostgreSQL 16, Python 3.12, Django 6.0.1. Le test `load.py` utilise 25 282 titres
synthétiques, 8 clients en boucle fermée, 930 recherches, connexion SQL renouvelée
par requête, sans réseau Deezer. La mesure finale inclut la mise en file durable
des enrichissements ; aucun worker fournisseur ne tourne pendant ce benchmark.

Avec deux threads d'indexation et `MEILI_MAX_INDEXING_MEMORY=256Mb` :

- Reconstruction : 5,49 s ; première recherche : 22,88 ms.
- Passage séquentiel chaud : p95 19,62 ms, p99 33,08 ms.
- Charge : 159 recherches/s ; p50 47,30 ms, p95 68,65 ms, p99 91,84 ms.
- Meilisearch : pointe cgroup 975 147 008 octets, courant 880 078 848 octets,
  disque 108,4 Mio après deux constructions depuis un conteneur neuf, avec une
  génération précédente contenant les mêmes 25 282 titres conservée.
- Typesense : pointe 145 645 568 octets, courant 133 324 800 octets, disque 14 Mio,
  sur les prototypes de 282 puis 5 363 documents, **pas sur 25 282**.

Ces deux dernières pointes ne constituent donc pas une comparaison à taille
égale. La comparaison de pertinence utilise bien les mêmes données. Le premier
prototype de 282 documents donnait environ 107 Mio courants pour Typesense et
440 Mio pour Meilisearch. Le test Meilisearch sans bornes d'indexation atteignait
3 485 839 360 octets de pointe : ne pas reprendre les réglages automatiques sur
le VPS audité. La limite d'indexation n'est pas une limite de mémoire totale.

Les mesures ne certifient ni la mémoire sur 3,73 millions de releases, ni une
latence de production. Pas de purge du cache OS : « première recherche » ne
signifie pas démarrage à froid du système. **Un hôte d'index séparé, ou une
validation à volume représentatif sur un hôte candidat isolé, est nécessaire
avant activation complète.** La limite 2 Gio du fichier de déploiement est un
garde-fou à valider, pas un dimensionnement du catalogue complet.

## Identités et cohérence

Un document par release et par entité artiste. La clé de regroupement associe
le titre complet normalisé et l'identifiant artiste stable. Les remixes et les
titres parenthétiques différents restent distincts ; les releases sans identité
artiste restent séparées. Les mots des parenthèses et invités sont recherchables.
Les crédits invités fournis par Deezer sont stockés et recherchables, ainsi que
le nom actuel de l’entité artiste. Les titres importés auparavant n’ont pas de
contributeurs si le payload n’en contenait pas ; aucun crédit n’est inventé.

Les triggers PostgreSQL produisent une outbox pour insertions, modifications
musicales et suppressions, y compris `bulk_create` et `QuerySet.update`. Les
changements d'artiste réindexent ses titres. Un seul consommateur détient un
verrou consultatif ; il relit toujours l'état actuel et acquitte seulement après
confirmation du moteur. Un événement ancien ne contient aucun document périmé
susceptible d'écraser l'état actuel. La reconstruction garde les événements jusqu'à
la bascule atomique des deux collections, après contrôle des nombres de documents.

La réhydratation SQL applique immédiatement les suppressions et blocages. Le
repli SQL consulte les champs complets, y compris les morceaux arrivés après
l'indexation. Comme toute recherche bornée, une requête ambiguë doit être affinée.
La pagination couvre une fenêtre stable de 400 candidats ; au-delà, l'API demande
un affinage. Un changement du catalogue entre deux pages peut modifier leur ordre.

L'ancienne API renvoie toujours une liste. `v=2` ajoute résultats, pagination,
état du complément et dégradation. Aucune donnée de manche n'entre dans le service.
Un payload sans audio est stocké comme réponse, mais reste exclu des manches.

## Comparaison supplémentaire à 25 282 documents

Les rapports `scale-*` utilisent strictement les mêmes documents pour les deux
moteurs. Typesense : indexation 0,266 s, p95 chaud 1,63 ms ; Meilisearch :
indexation 1,281 s, p95 chaud 1,72 ms. Recall@20 synthétique de validation :
96,59 % contre 100 %. Le corpus comporte davantage de distracteurs, ce qui
renforce le choix de pertinence. Ces temps d'import moteur seuls ne comprennent
pas l'export SQL, l'outbox et la bascule mesurés par `load.py`.

La mesure finale utilise le stockage des crédits invités et le traitement des
événements d'artiste en lots de 500. Ce corpus n'est toutefois pas un test
d'une discographie comptant des millions de contributions.

## Documentation des interfaces

Le prototype utilise les paramètres de
[recherche Typesense 29.0](https://typesense.org/docs/29.0/api/search.html) et
[l’API de recherche Meilisearch](https://www.meilisearch.com/docs/reference/api/search/search-with-post).
Les appels de création, acquittement de tâche et bascule ont été vérifiés par
les tests contre les versions épinglées, sans client SDK non verrouillé.

Les blocages fermes sont désormais vérifiés aussi pour une manche dirigée, par
une sous-requête bénéficiant d’un index partiel. Le cache des exclusions de qualité
reste distinct. Cela évite de jouer un artiste que la recherche vient de masquer,
y compris après un `QuerySet.update` contournant `Artist.save()`. Deux anciennes
assertions autorisant les artistes bloqués en jeu dirigé/interdisant toute
sous-requête ont été remplacées par les attentes correspondant à cette cohérence.
