#!/data/data/com.termux/files/usr/bin/bash
set -e
cd "$HOME/anime_organizer"
python apply_correctif_v39.py
if ! git diff --quiet -- lib/screens/pc_sync_screen.dart; then
  git add lib/screens/pc_sync_screen.dart
  git commit -m 'V39: corriger apostrophes dans boutons connexion distante'
  git push
  echo 'Correctif envoye sur GitHub : consulte Actions.'
else
  echo 'Aucune modification a publier (correctif deja applique ou commit existant).'
fi
