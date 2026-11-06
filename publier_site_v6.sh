#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_site_v6.py
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
 echo 'Ce dossier ne contient pas de depot Git.';exit 1
fi
git add docs/index.html docs/assets/apercu_bibliotheque.webp docs/assets/apercu_fiche.webp docs/assets/apercu_filtres.webp tool/apply_site_v6.py publier_site_v6.sh
if git diff --cached --quiet;then echo 'Site deja a jour.';exit 0;fi
git commit -m 'Site V6: trois apercus fideles avec contenus fictifs'
git push origin HEAD:main
printf '
Mise a jour V6 envoyee a GitHub Pages.
'
