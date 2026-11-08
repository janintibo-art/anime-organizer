#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
[ -d .git ] || { echo 'Depot Git absent'; exit 1; }
python tool/apply_update_v27.py
if git diff --quiet -- .github/workflows/build.yml; then
  echo 'Aucun changement à publier (V27 déjà appliquée).'
  exit 0
fi
git add .github/workflows/build.yml
git commit -m 'V27: verification Defender et SHA256 pour releases'
git push origin HEAD:main
echo 'V27 envoyée sur GitHub.'
