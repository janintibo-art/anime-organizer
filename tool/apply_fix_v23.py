#!/usr/bin/env python3
"""Targeted compile fix for Anime Organizer V23."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
meta = root / 'lib/models/anime_meta.dart'
tmdb = root / 'lib/services/tmdb_api.dart'

if not all(f.is_file() for f in (meta, tmdb)):
    sys.exit('Erreur : dossier anime_organizer non trouvé ou incomplet.')

changes = {}
def once(src, old, new, name):
    if old in src:
        if src.count(old) != 1:
            sys.exit(f'Erreur : {name} est ambigu ({src.count(old)} occurrences). Rien modifié.')
        return src.replace(old,new,1)
    if new in src:
        return src
    sys.exit(f'Erreur : motif {name} introuvable. Rien modifié.')

s = meta.read_text(encoding='utf-8')
s = once(s, '    required this.title,\n    this.titleNative,',
         '    required this.title,\n    this.originLanguage,\n    this.titleNative,', 'constructeur origine')
s = once(s, "        'title': title,\n        'titleNative': titleNative,",
         "        'title': title,\n        'originLanguage': originLanguage,\n        'titleNative': titleNative,", 'sérialisation origine')
s = once(s, "        title: j['title'] as String? ?? 'Sans titre',\n        titleNative:",
         "        title: j['title'] as String? ?? 'Sans titre',\n        originLanguage: j['originLanguage'] as String?,\n        titleNative:", 'désérialisation origine')
changes[meta] = s

s = tmdb.read_text(encoding='utf-8')
s = once(s, "    final genreIds = (item['genre_ids'] as List? ?? const [])\n        .map((e) => _genres[e as int])\n        .whereType<String>()\n        .where((g) => g.isNotEmpty)\n        .toList();",
         "    final List<String> genreIds = (item['genre_ids'] as List? ?? const [])\n        .map((e) => _genres[e as int])\n        .whereType<String>()\n        .where((g) => g.isNotEmpty)\n        .toList();", 'liste genres typée')
s = once(s, "      titleRomaji: item['original_name']?.toString(),\n      imageUrl:",
         "      titleRomaji: item['original_name']?.toString(),\n      originLanguage: item['original_language']?.toString(),\n      imageUrl:", 'langue d’origine TV')
changes[tmdb] = s

for path, result in changes.items():
    if path.read_text(encoding='utf-8') != result:
        path.write_text(result, encoding='utf-8')
        print('Corrigé :', path.relative_to(root))
    else:
        print('Déjà corrigé :', path.relative_to(root))
print('Correctif de compilation V23 appliqué.')
