#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/anime_organizer"
python3 correctif_v34.py
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Projet Git introuvable dans $PWD. Le fichier a ete corrige localement."
  exit 1
fi
git add lib/screens/player_screen.dart
if git diff --cached --quiet -- lib/screens/player_screen.dart; then
  echo 'Aucune modification a envoyer.'
else
  git commit -m "fix(v34): remove const from dynamic audio confirmation SnackBar"
  git push
  echo 'Correctif V34 envoye sur GitHub.'
fi
