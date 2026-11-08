#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_update_v25.py
if command -v git >/dev/null 2>&1; then
 git add lib/models/anime.dart lib/screens/detail_screen.dart pubspec.yaml
 if ! git diff --cached --quiet; then
   git commit -m 'V25: panoramas personnels et fond de secours sobre'
   git push
 else
   echo 'Aucune modification a publier.'
 fi
else
 echo 'Git indisponible ; fichiers modifies localement.'
fi
