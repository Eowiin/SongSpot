# Recette Flutter — Android, iOS et web

Oui, cette livraison comporte des changements Flutter. Effectuer ces contrôles
sur les trois plateformes, avec un backend contenant la nouvelle version
(local/recette, ou production après son déploiement autorisé).

Dans les trois parcours **choix d’artiste, partie solo et duel** :

1. Chercher un artiste ou titre connu, puis une saisie courte de deux lettres :
   résultats affichés, aucun chargement interminable. Dans les recherches de
   titres, vérifier `q&a Drake` et un titre complet avec parenthèses et artiste.
2. Taper rapidement, effacer et changer de saisie : les anciens résultats ne
   doivent pas revenir. Quitter l’écran ou passer à la manche suivante pendant
   le chargement : pas de résultat ni de message de la manche précédente.
3. Chercher un élément absent du catalogue local : un éventuel complément doit
   apparaître sans retaper. Si rien n’est trouvé, afficher un état vide clair ;
   une faute de frappe ne garantit pas un résultat avec PostgreSQL seul.
4. Couper la connexion puis la rétablir et relancer une recherche : message
   compréhensible et récupération possible, sans spinner permanent.
5. Choisir la même chanson et le même artiste depuis une autre édition (best-of
   au lieu de l’album original) : la réponse doit être acceptée. Vérifier aussi
   ce cas sur une partie sans jeton serveur si disponible en recette.
6. Sélectionner un résultat : l’artiste ou la réponse est bien pris en compte,
   et la partie continue normalement. Vérifier les messages en français et en
   anglais si ces deux langues sont proposées sur l’appareil.

Les 96 tests Flutter et l’analyse statique ont déjà passé avec Flutter 3.41.9 /
Dart 3.11.5, sans changement du lockfile. Ils ne remplacent pas les builds et
ces essais sur appareils. Utiliser les fichiers Firebase habituels du MacBook
pour les builds Android/iOS, puis publier la mise à jour mobile après validation.
