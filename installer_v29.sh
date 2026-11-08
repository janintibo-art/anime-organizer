#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
[ -d .git ] || { echo 'Depot Git absent'; exit 1; }
python tool/apply_update_v29.py
if git diff --quiet -- .github/workflows/build.yml && git ls-files --error-unmatch tool/audit_windows_v29.ps1 >/dev/null 2>&1; then
  echo 'V29 deja installee : aucune modification.'
  exit 0
fi
git add .github/workflows/build.yml tool/audit_windows_v29.ps1
git commit -m 'V29: audit de securite individuel des binaires Windows'
git push origin HEAD:main
echo 'V29 publiee sur GitHub.'
