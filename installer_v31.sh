#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/anime_organizer"
python correctif_v31.py
if ! command -v git >/dev/null; then pkg install -y git; fi
git add lib/screens/player_screen.dart .github/workflows/build.yml tool/audit_windows_v29.ps1
git commit -m "V31: capturer la position video via FFmpeg embarque" || true
git push origin HEAD
