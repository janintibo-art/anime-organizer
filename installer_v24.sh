#!/data/data/com.termux/files/usr/bin/bash
set -e
cd "$HOME/anime_organizer"
python tool/apply_update_v24.py
if command -v git >/dev/null; then
  git add lib/services/library_controller.dart lib/screens/detail_screen.dart lib/screens/home_screen.dart lib/services/scanner.dart
  if ! git diff --cached --quiet; then
    git commit -m "V24: catégorie À identifier et analyse films isolés"
    git push
  else
    echo 'Aucun changement à publier.'
  fi
else
  echo 'Git absent : fichiers modifiés localement, publication manuelle nécessaire.'
fi
