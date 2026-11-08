#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python apply_correctif_v39.py
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo 'Code corrige localement. Dossier non relie a Git : publication a faire manuellement.'
  exit 0
fi
git add lib/screens/home_screen.dart lib/screens/pc_sync_screen.dart
if git diff --cached --quiet; then
  echo 'Aucun changement a envoyer.'
  exit 0
fi
git commit -m 'V39 correctif : navigation Android et connexion distante Tailscale'
git push
printf '\nCorrectif envoye sur GitHub. Verifier Actions.\n'
