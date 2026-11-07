#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_update_v23.py
python -m py_compile tool/apply_update_v23.py
git add lib tool/apply_update_v23.py installer_v23.sh
if ! git diff --cached --quiet; then
 git commit -m 'v23: films animes, meilleure identification et categories automatiques'
 git push origin HEAD
else
 echo 'Aucune nouvelle modification à envoyer.'
fi
