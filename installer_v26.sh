#!/usr/bin/env bash
set -euo pipefail
PROJECT="$HOME/anime_organizer"
cd "$PROJECT"
if [ ! -d .git ]; then echo 'Depot Git absent dans ~/anime_organizer'; exit 1; fi
python patch_v26.py
python -m py_compile patch_v26.py
git add lib/models/anime.dart lib/screens/player_screen.dart lib/screens/detail_screen.dart lib/services/capture_gallery.dart
git diff --cached --check
if git diff --cached --quiet; then echo 'V26 deja appliquee'; exit 0; fi
git commit -m 'V26: captures F2, galerie par anime et diaporama'
git push
