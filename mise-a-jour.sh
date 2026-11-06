#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
if [ ! -d .git ]; then echo 'Depot Git introuvable dans ~/anime_organizer'; exit 1; fi
python tool/apply_update_v4.py
# Ne jamais inclure de caches Python dans les commits.
find tool -type d -name __pycache__ -prune -exec rm -rf {} +
git add lib/models/anime.dart lib/services/library_controller.dart lib/services/backdrop_service.dart lib/screens/detail_screen.dart .github/workflows/build.yml docs/ README.md tool/apply_update_v4.py mise-a-jour.sh
if git diff --cached --quiet; then echo 'Rien a publier.'; exit 0; fi
git commit -m 'V4 - galerie panoramique et site officiel avec Releases'
git push origin HEAD:main
