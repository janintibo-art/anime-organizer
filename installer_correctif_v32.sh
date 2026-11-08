#!/usr/bin/env bash
set -euo pipefail
PROJECT="$HOME/anime_organizer"
cd "$PROJECT"
python3 correctif_v32.py
if ! git diff --quiet -- lib/screens/detail_screen.dart; then
  git add -- lib/screens/detail_screen.dart
  git commit -m "fix: V32 musique, fermeture du panneau Flutter"
  git push origin HEAD
  printf '\nCorrectif envoyé sur GitHub. Vérifie Actions.\n'
else
  echo 'Aucune modification à envoyer (correctif déjà appliqué).'
fi
