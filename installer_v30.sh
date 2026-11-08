#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
python3 tool/apply_update_v30.py
git add lib/screens/player_screen.dart
git commit -m 'v30: precise paused captures, F2 F3 feedback and preview' || true
git push origin HEAD:main
