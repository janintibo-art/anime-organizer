#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_update_v28.py
if command -v git >/dev/null 2>&1; then
  git add lib/models/anime.dart lib/screens/detail_screen.dart
  if ! git diff --cached --quiet; then
    git commit -m 'V28: galerie visuelle, ordre des captures, suppression et fondu'
    git push origin HEAD:main
  else
    echo 'Aucune modification à publier.'
  fi
fi
