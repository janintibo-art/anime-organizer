# V44 – Sauvegardes datées et restauration Windows

- Enregistrement de versions journalières avant écrasement de `library.json` (30 copies maximum).
- Windows : dossier Documents/Anime Organizer/Sauvegardes (indépendant du dossier AppData et de l'installation).
- Bouton Sauvegarder maintenant, historique des copies, aperçu du nombre de séries, confirmation avant restauration complète.
- Copie de sécurité de l'état courant avant restauration ; réglages, dossiers, fiches, favoris, progression, wishlist et correspondances inclus.
- Export manuel existant préservé ; les vidéos ne sont pas copiées.
- ATTENTION : pour résister à une panne du disque ou à un effacement de Documents, exporter aussi régulièrement vers un support externe.
- Le premier instantané quotidien est pris au premier enregistrement de la journée et contient l'état précédent. Le fichier de travail et le .bak sont préservés.
- APK et EXE : compilation et essais réels à valider dans GitHub Actions et sur les appareils.
