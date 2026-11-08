# V42 — Serveur Windows unique et persistant

- Le serveur PC ne se coupe plus lorsqu’on quitte l’écran Synchronisation.
- À la réouverture, l’application retrouve un serveur déjà actif avec son code enregistré, sans créer de deuxième processus.
- Le compagnon Python Windows utilise un mutex nommé pour interdire plusieurs instances simultanées sur le même port.
- Le bouton Arrêter reste un arrêt volontaire du serveur; les lectures à distance ne fonctionnent plus jusqu’au redémarrage.
- Aucun changement du protocole, du port 8765, ni des fichiers de bibliothèque.

**Tests à effectuer sous Windows après compilation GitHub :**
1. Démarrer le serveur, quitter l’écran puis y revenir : code affiché sans nouveau lancement.
2. Fermer/réouvrir Anime Organizer : serveur réutilisé sans doublon.
3. Vérifier la lecture Android en 4G, y compris quand la fenêtre de synchronisation est fermée.
4. Arrêter volontairement le serveur : disparition du processus, puis redémarrage possible.
5. Vérifier qu’un seul AnimeOrganizerSyncServer.exe apparaît dans le Gestionnaire des tâches.
