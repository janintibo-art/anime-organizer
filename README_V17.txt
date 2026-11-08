Anime Organizer V17 - diagnostics streaming

- Le serveur Python expose /v1/capabilities avec authentification par code.
- Detecte FFmpeg dans le dossier du serveur ou dans le PATH.
- Android n'affiche les modes 720p et 480p que si FFmpeg est operationnel.
- En cas de serveur V15 ou diagnostic indisponible, le mode original reste utilisable.
- Aucune bibliotheque, video, credential ou progression ne sont modifies.

Installation Termux :
unzip -o /sdcard/Download/anime_organizer_v17.zip -d ~ && bash ~/anime_organizer/mise-a-jour.sh

Le PC et Android doivent avoir la nouvelle version installee apres le build.
Le serveur est pour le Wi-Fi prive ou Tailscale, pas pour exposition Internet.
