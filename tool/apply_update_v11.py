#!/usr/bin/env python3
"""V11: le bandeau utilise le panorama paysage sans zoomer l'affiche verticale.
Ne modifie que le rendu du bandeau de la fiche.
"""
from pathlib import Path

path = Path('lib/screens/detail_screen.dart')
if not path.is_file():
    raise SystemExit('Erreur : lib/screens/detail_screen.dart introuvable. Lance le script depuis le depot anime_organizer.')
s = path.read_text(encoding='utf-8')
old = '''            // L'image garde ses couleurs : plus d'aplat noir par-dessus.
            PosterImage(
              anime: anime,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),'''
new = '''            // Bandeau cinema : preferer le panorama 16:9, jamais
            // l'affiche portrait agrandie jusqu'a couper les visages.
            if (anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: anime.backdropUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorWidget: (_, __, ___) => Container(
                  color: Palette.ink,
                  alignment: Alignment.center,
                  child: PosterImage(
                    anime: anime,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                  ),
                ),
              )
            else
              Container(
                color: Palette.ink,
                alignment: Alignment.center,
                child: PosterImage(
                  anime: anime,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),'''
if new in s:
    print('V11 deja appliquee : aucune modification necessaire.')
elif s.count(old) != 1:
    raise SystemExit(f'Motif de bandeau inattendu ({s.count(old)} occurrence). Aucun fichier modifie. Envoie le message pour ajuster le correctif.')
else:
    s = s.replace(old,new,1)
    path.write_text(s, encoding='utf-8')
    print('V11 : bandeau panoramique centre, affiche verticale non zoomee.')
