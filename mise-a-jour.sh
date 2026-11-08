#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python tool/apply_update_v22.py
python -m py_compile tool/sync_server.py tool/apply_update_v22.py
git add lib/screens/player_screen.dart lib/screens/remote_episodes_screen.dart lib/screens/pc_sync_screen.dart tool/sync_server.py
git diff --cached --check
if ! git diff --cached --quiet; then
  git commit -m "V22: journal de progression Android et import Windows"
  git push origin HEAD:main
else
  echo 'V22 deja appliquee ou aucune modification a publier.'
fi
