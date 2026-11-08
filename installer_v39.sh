#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="$HOME/anime_organizer"
cd "$ROOT"
python3 apply_v39.py
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo 'Dossier Git absent : modifications locales appliquees uniquement.'
  exit 0
fi
git add lib/screens/home_screen.dart lib/screens/pc_sync_screen.dart tool/sync_server.py
if git diff --cached --quiet; then
  echo 'Aucun changement a envoyer.'
  exit 0
fi
git commit -m 'V39: barre Android compacte et découverte LAN du serveur PC'
git push
printf '\nV39 envoyée. Vérifie GitHub Actions avant installation.\n'
