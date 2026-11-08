#!/usr/bin/env python3
"""Patch local sûr. Vérifie les ancres avant toute modification."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
changes = {}

def load(path):
    p = root / path
    if not p.exists():
        raise RuntimeError(f'Fichier absent : {path}. Installer les versions précédentes.')
    return p.read_text(encoding='utf-8')

def replace_once(path, old, new):
    s = changes.get(path, load(path))
    if new in s:
        return
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f'{path} : emplacement attendu {count} fois (1 requis). Aucun fichier modifié.')
    changes[path] = s.replace(old, new, 1)

controller = 'lib/services/library_controller.dart'
replace_once(controller,
    '    anime.apiTitle = meta.title;\n    anime.nativeTitle = meta.titleNative;',
    '    anime.apiTitle = meta.title;\n    // Une fiche corrigée ne doit pas conserver un ancien titre français.\n    anime.frenchTitle = null;\n    anime.nativeTitle = meta.titleNative;')
# La source western combine les bases même quand une clé TMDB existe.
replace_once(controller,
    "    final preferredSource = isWestern\n        ? (settings.tmdbKey.trim().isNotEmpty ? 'tmdb' : 'tvmaze')\n        : settings.metaSource;",
    "    final preferredSource = isWestern\n        ? 'western'\n        : settings.metaSource;")
replace_once(controller,
    "        final source = isWestern\n            ? (settings.tmdbKey.trim().isEmpty ? 'tvmaze' : 'tmdb')\n            : settings.metaSource;",
    "        final source = isWestern ? 'western' : settings.metaSource;")
replace_once(controller,
    """        meta = await MetadataService.smartSearch(english,
            source: preferredSource,
            episodeCount: anime.episodes.where((e) => !e.bonus).length);""",
    """        meta = await MetadataService.smartSearch(english,
            source: preferredSource,
            episodeCount: anime.episodes.where((e) => !e.bonus).length,
            tmdbKey: settings.tmdbKey);""")

metadata = 'lib/services/metadata_service.dart'
replace_once(metadata,
    "      case 'tvmaze':\n        return TvmazeApi.search(title, limit: limit);",
    """      case 'tvmaze':
        return TvmazeApi.search(title, limit: limit);
      case 'western':
        // TVmaze sans clé + TMDB avec clé : deux chances de trouver
        // les séries animées occidentales, sans doublons.
        final tv = await TvmazeApi.search(title, limit: limit);
        if (tmdbKey.trim().isEmpty) return tv;
        final tmdb = await TmdbApi.search(title, tmdbKey, limit: limit);
        final seen = <String>{};
        final merged = <AnimeMeta>[];
        for (final item in [...tmdb, ...tv]) {
          final key = stripAccents(item.title)
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (seen.add(key)) merged.add(item);
        }
        merged.sort((a, b) => similarity(title, b.title)
            .compareTo(similarity(title, a.title)));
        return merged.take(limit).toList();""")

detail='lib/screens/detail_screen.dart'
replace_once(detail,
    "import '../services/metadata_service.dart';",
    "import '../services/metadata_service.dart';\nimport '../services/scanner.dart';")
replace_once(detail,
    "    final controller = TextEditingController(text: anime.folderTitle);",
    "    final suggested = Scanner.titleFromFiles(anime.episodes);\n    final controller = TextEditingController(\n        text: suggested ?? anime.folderTitle);")
replace_once(detail,
    """    final results = await MetadataService.searchMany(
      query,
      source: (anime.category == 'western' || anime.category == 'adult')
          ? (library.settings.tmdbKey.trim().isEmpty ? 'tvmaze' : 'tmdb')
          : library.settings.metaSource,
      tmdbKey: library.settings.tmdbKey,
    );""",
    """    // Si la catégorie a été mal détectée, la correction doit aussi
    // proposer les résultats occidentaux (TMDB + TVmaze).
    final western = anime.category == 'western' || anime.category == 'adult';
    final primary = await MetadataService.searchMany(
      query,
      source: western ? 'western' : library.settings.metaSource,
      tmdbKey: library.settings.tmdbKey,
    );
    final alternatives = western
        ? <AnimeMeta>[]
        : await MetadataService.searchMany(query, source: 'western',
            tmdbKey: library.settings.tmdbKey);
    final found = <AnimeMeta>[];
    final seen = <String>{};
    for (final result in [...primary, ...alternatives]) {
      final key = result.source + ':' + (result.sourceId?.toString() ?? result.title);
      if (seen.add(key)) found.add(result);
    }
    found.sort((a, b) => MetadataService.similarity(query, b.title)
        .compareTo(MetadataService.similarity(query, a.title)));
    final results = found.take(20).toList();""")

# Validation globale avant toute écriture : évite un patch partiellement appliqué.
if not changes:
    print('V9 déjà appliquée.')
else:
    for path, content in changes.items():
        (root / path).write_text(content, encoding='utf-8')
        print('Modifié :', path)
print('V9 OK. Anciennes fiches : utiliser Corriger la fiche pour purger leurs champs erronés.')
