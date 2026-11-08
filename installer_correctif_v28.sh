#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_hotfix_v28.py
if git diff --quiet -- lib/screens/detail_screen.dart lib/screens/player_screen.dart; then
  echo 'Aucune modification à publier.'
  exit 0
fi
git add lib/screens/detail_screen.dart lib/screens/player_screen.dart
git commit -m 'V28: corriger galerie et raccourcis F2 F3 plein ecran'
git push origin HEAD:main
printf '\nCorrectif publié. Vérifier GitHub Actions.\n'
