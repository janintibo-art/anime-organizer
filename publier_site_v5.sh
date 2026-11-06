#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_site_v5.py
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo 'ERREUR : le dossier anime_organizer n est pas un depot Git.';exit 1
fi
if [ -z "$(git status --porcelain -- docs/index.html docs/assets tool/apply_site_v5.py publier_site_v5.sh)" ]; then
  echo 'Aucun changement a publier.';exit 0
fi
git add docs/index.html docs/assets/apercu_bibliotheque.webp docs/assets/apercu_fiche.webp tool/apply_site_v5.py publier_site_v5.sh
git commit -m 'Site V5: galerie fidele de demonstration Anime Organizer'
git push origin HEAD:main
printf '\nSite V5 publie sur la branche main.\n'
