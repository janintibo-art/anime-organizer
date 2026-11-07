#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/anime_organizer"
cd "$ROOT"
test -f lib/screens/player_screen.dart || { echo 'Projet anime_organizer introuvable'; exit 1; }
python3 tool/patch_v33.py
git add lib/screens/player_screen.dart lib/screens/detail_screen.dart lib/services/anime_themes_catalog.dart tool/patch_v33.py installer_v33.sh
if git diff --cached --quiet; then
  echo 'V33 deja appliquee ; aucun commit necessaire.'
  exit 0
fi
git commit -m 'V33: F4 extraction audio et recherche AnimeThemes'
git push
printf '\nV33 envoyee ; verifier les builds GitHub Actions.\n'
