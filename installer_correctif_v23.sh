#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_fix_v23.py
if ! git diff --quiet -- lib/models/anime_meta.dart lib/services/tmdb_api.dart; then
  git add lib/models/anime_meta.dart lib/services/tmdb_api.dart
  git commit -m "fix: correct V23 TMDB metadata compile errors"
  git push
  echo "Correction publiée sur GitHub. Vérifie Actions."
else
  echo "Aucune modification à envoyer (correctif déjà appliqué)."
fi
