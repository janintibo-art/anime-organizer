#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python installer_v35.py
if ! git diff --quiet -- installer/anime_organizer.iss || [ -n "$(git ls-files --others --exclude-standard installer/assets)" ]; then
  git add installer/anime_organizer.iss installer/assets/
  git commit -m "V35: installateur Anime Neon Library" || true
  git push
  echo 'Correctif V35 envoye sur GitHub.'
else
  echo 'Aucun changement a publier (V35 deja appliquee).'
fi
