#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/anime_organizer"
cd "$ROOT"
if [ ! -f pubspec.yaml ] || [ ! -f lib/screens/player_screen.dart ] || [ ! -f lib/models/anime.dart ]; then
  echo 'Projet anime_organizer introuvable dans ~/anime_organizer' >&2
  exit 1
fi
python3 tool/patch_v34.py
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add lib/models/anime.dart lib/screens/detail_screen.dart lib/screens/player_screen.dart lib/services/theme_audio_service.dart
  if ! git diff --cached --quiet; then
    git commit -m 'V34 : bibliotheque sonore par anime, fichiers nommes, lecture multiple'
    git push
  else
    echo 'Aucune nouvelle modification a publier.'
  fi
else
  echo 'Fichiers mis a jour. Ce repertoire ne contient pas de depot Git.'
fi
