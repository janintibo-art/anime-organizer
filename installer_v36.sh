#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$HOME/anime_organizer"
for f in docs/index.html docs/assets/neon_hero.webp docs/assets/neon_banner.webp docs/assets/neon_icon.webp; do
  [ -s "$f" ] || { echo "Fichier manquant ou vide : $f" >&2; exit 1; }
done
python - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
class Checker(HTMLParser):
    def error(self,message): raise ValueError(message)
p=Path('docs/index.html'); content=p.read_text(encoding='utf-8')
assert 'Anime Organizer' in content and '#telecharger' in content
checker=Checker(); checker.feed(content); checker.close()
for rel in ['neon_hero.webp','neon_banner.webp','neon_icon.webp']:
    assert (Path('docs/assets')/rel).stat().st_size > 1000
print('V36 : fichiers et structure HTML vérifiés.')
PY
# Ne touche pas au code Flutter ni aux assets de l'installateur.
if [ -n "$(git status --porcelain -- docs/index.html docs/assets/neon_hero.webp docs/assets/neon_banner.webp docs/assets/neon_icon.webp)" ]; then
  git add docs/index.html docs/assets/neon_hero.webp docs/assets/neon_banner.webp docs/assets/neon_icon.webp
  git commit -m "V36: refonte du site Anime Neon Library et fonctions recentes"
  git push
  echo 'Site V36 publié sur le dépôt. Vérifie la page GitHub Pages.'
else
  echo 'Site V36 déjà appliqué : aucun changement.'
fi
