# Anime Organizer — V40 · bibliothèque PC / Android unifiée

## Modifications

- L'écran Bibliothèque Android charge automatiquement l'association V39 et le catalogue `/v1/library` du PC.
- Les séries distantes sont affichées dans la bibliothèque principale, avec affiches si une URL HTTPS est disponible, titres, nombre d'épisodes et progression du PC.
- Filtre de source : **Toutes**, **Téléphone**, **PC**. La recherche textuelle fonctionne sur le catalogue distant.
- Un clic sur une série PC ouvre le lecteur d'épisodes distant déjà éprouvé en V39.
- Cache local de **métadonnées seulement** pour présenter les titres même si le PC est hors ligne. Impossible de lire une vidéo sans serveur connecté.
- L'écran Synchronisation publie aussitôt son catalogue vers la bibliothèque principale, sans seconde requête HTTP.

## Validation conseillée après compilation

1. Sur Windows, démarrer l'unique serveur de synchronisation. Vérifier Tailscale.
2. Sur Android, ouvrir l'onglet Bibliothèque. Avec un PC mémorisé, attendre le chargement. Vérifier « PC connecté » et les séries.
3. Tester **PC**, **Téléphone**, **Toutes**, la recherche et l'ouverture d'une vidéo.
4. Fermer l'APK, la relancer et vérifier la reconnexion sans code.
5. Couper Tailscale : le catalogue en cache reste visible mais la lecture est désactivée. Réactiver Tailscale et toucher Actualiser.
6. Vérifier une bibliothèque locale Android et les filtres existants.

## Limitations

- Les filtres « genre », « catégorie » et « VF » ne sont pas encore pris en charge pour les séries PC, car l'API du serveur ne transmet pas ces métadonnées.
- La synchronisation des progressions n'a pas été modifiée.
- Aucun binaire APK/EXE n'est inclus ; compiler via GitHub Actions.
- La correction des processus Windows multiples n'est pas comprise dans ce patch Android ; ne pas confondre avec une correction déjà testée.
