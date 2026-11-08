#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/anime_organizer"
if [ ! -d .git ]; then echo 'Dépôt ~/anime_organizer introuvable.' >&2; exit 1; fi
if [ ! -f docs/index.html ]; then echo 'Fichier docs/index.html introuvable.' >&2; exit 1; fi
if [ -z "$(git status --porcelain -- docs/index.html)" ]; then echo 'Aucune modification du site à publier.'; exit 0; fi
git add -- docs/index.html
git commit -m 'V38: navigation par rubriques et galerie mobile responsive'
git push origin "$(git branch --show-current)"
echo 'V38 envoyée. Vérifier GitHub Pages.'
