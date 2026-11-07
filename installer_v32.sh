#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/anime_organizer"
cd "$ROOT"
[ -f lib/screens/detail_screen.dart ] || { echo 'Projet anime_organizer introuvable'; exit 1; }
python3 tool/patch_v32.py
if git diff --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo 'Aucune modification détectée.'
  exit 0
fi
git add lib/screens/detail_screen.dart lib/models/anime.dart lib/services/theme_audio_service.dart tool/patch_v32.py installer_v32.sh
git commit -m 'V32: musique de fiche, import et extraction FFmpeg'
git push
printf '\nV32 envoyée. Consulter GitHub Actions pour vérifier la compilation.\n'
