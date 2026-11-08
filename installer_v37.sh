#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python installer_v37.py
git add installer/anime_organizer.iss installer/assets/wizard_back.png .github/workflows/build.yml
git commit -m "V37 : vrai theme anime sombre sur installateur, icone restauree" || { echo "Aucune modification a publier"; exit 0; }
git push
