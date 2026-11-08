Anime Organizer — Correctif de compilation V23

Corrige :
- originLanguage manquant dans le constructeur AnimeMeta
- originLanguage absent du JSON (préservation des valeurs)
- typage explicite List<String> des genres TMDB
- renseigne la langue d'origine des séries TMDB

Installation depuis Termux (ZIP dans Téléchargements) :
unzip -o /sdcard/Download/anime_organizer_correctif_v23.zip -d ~ && bash ~/anime_organizer/installer_correctif_v23.sh

N'efface aucune vidéo ni bibliothèque.
Relance GitHub Actions après publication. Aucun test Flutter local n'a été effectué.
