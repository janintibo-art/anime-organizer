#!/usr/bin/env python3
"""Anime Organizer: categorie animation, detection fichiers, fond de fiche."""
from pathlib import Path
import sys

root=Path(__file__).resolve().parents[1]

def replace(path,old,new):
    p=root/path
    if not p.exists(): raise RuntimeError(f'Fichier absent: {path}')
    src=p.read_text(encoding='utf-8')
    if new in src:
        print('Déjà appliqué:',path)
        return
    count=src.count(old)
    if count!=1: raise RuntimeError(f'{path}: motif non unique ou absent ({count}): {old[:65]!r}')
    p.write_text(src.replace(old,new,1),encoding='utf-8')
    print('OK:',path)

model='lib/models/anime.dart'
replace(model,"  bool favorite;\n", "  bool favorite;\n\n  /// anime | western | adult | other. Anciennes fiches = anime.\n  String category;\n")
replace(model,"    this.favorite = false,\n", "    this.favorite = false,\n    this.category = 'anime',\n")
replace(model,"        'favorite': favorite,\n", "        'favorite': favorite,\n        'category': category,\n")
replace(model,"        favorite: j['favorite'] as bool? ?? false,\n", "        favorite: j['favorite'] as bool? ?? false,\n        category: j['category'] as String? ?? 'anime',\n")

scanner='lib/services/scanner.dart'
replace(scanner,"  /// Tri naturel : « Episode 2 » avant « Episode 10 ».\n", """  /// Une série dont le dossier est obscur peut être reconnue via ses vidéos.
  /// On ne garde que le préfixe précédant un marqueur de saison/épisode.
  static String? titleFromFiles(List<Episode> episodes) {
    if (episodes.isEmpty) return null;
    final names = <String>[];
    final marker = RegExp(
      r'\\b(?:s\\d{1,2}[ ._-]*e\\d{1,3}|saison[ ._-]*\\d{1,2}|'
      r'season[ ._-]*\\d{1,2}|[eé]pisode[ ._-]*\\d{1,3}|ep[ ._-]*\\d{1,3})\\b',
      caseSensitive: false,
    );
    for (final e in episodes.take(12)) {
      final m = marker.firstMatch(e.name);
      if (m == null || m.start < 4) continue;
      final candidate = cleanTitle(e.name.substring(0, m.start));
      if (candidate.length >= 4 && candidate.length <= 100) names.add(candidate);
    }
    if (names.isEmpty) return null;
    final counts = <String, int>{};
    for (final name in names) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    // Un fichier unique explicite suffit ; sinon confirmation par deux vidéos.
    if (episodes.length > 1 && sorted.first.value < 2) return null;
    return sorted.first.key;
  }

  /// Tri naturel : « Episode 2 » avant « Episode 10 ».
""")

controller='lib/services/library_controller.dart'
replace(controller,"      for (final item in found) {\n        final old = existing[item.id];", """      for (final item in found) {
        // Les corrections existantes doivent toujours primer sur le scan.
        final inferred = Scanner.titleFromFiles(item.episodes);
        if (inferred != null &&
            (item.folderTitle.length < 4 ||
             RegExp(r'^(serie|anime|saison|season|videos?|new folder|dossier)[ _-]*\\d*$',
               caseSensitive: false).hasMatch(item.folderTitle))) {
          item.folderTitle = inferred;
        }
        final old = existing[item.id];""")
replace(controller,"          merged.add(item);\n          discovered++;", """          // Catégorie initiale ; l'utilisateur peut ensuite la modifier.
          item.category = _guessCategory(item.folderTitle);
          merged.add(item);
          discovered++;""")
replace(controller,"  /// Recupere image, synopsis et genres pour une serie.\n", """  static String _guessCategory(String title) {
    final t = MetadataService.stripAccents(title);
    if (RegExp(r'\\b(south park|family guy|american dad|rick and morty|'
        r'bojack horseman|big mouth|solar opposites)\\b').hasMatch(t)) {
      return 'adult';
    }
    if (RegExp(r'\\b(the simpsons|simpsons|les simpson|futurama|'
        r'gravity falls|adventure time|regular show|scooby doo|'
        r'batman the animated series)\\b').hasMatch(t)) {
      return 'western';
    }
    return 'anime';
  }

  /// Recupere image, synopsis et genres pour une serie.
""")
replace(controller,"    final query = overrideQuery ?? anime.folderTitle;\n    final count", """    final query = overrideQuery ?? anime.folderTitle;
    final fileTitle = Scanner.titleFromFiles(anime.episodes);
    final count""")
replace(controller,"    var meta = await MetadataService.smartSearch(\n      resolved ?? query,\n      source: settings.metaSource,", """    final preferredSource = (anime.category == 'western' || anime.category == 'adult')
        ? 'tmdb'
        : settings.metaSource;
    var meta = await MetadataService.smartSearch(
      resolved ?? query,
      source: preferredSource,""")
replace(controller,"    // 3. Rien en ligne mais la base locale connait la serie", """    // Le titre inclus dans le fichier est souvent meilleur que le dossier.
    // Une recherche alternative ne remplace jamais une identification validée.
    if (meta == null && overrideQuery == null && fileTitle != null &&
        MetadataService.similarity(fileTitle, query) < 0.95) {
      meta = await MetadataService.smartSearch(fileTitle,
          source: preferredSource, episodeCount: count,
          tmdbKey: settings.tmdbKey);
    }

    // 3. Rien en ligne mais la base locale connait la serie""")
replace(controller,"            source: settings.metaSource,\n            episodeCount: anime.episodes", "            source: preferredSource,\n            episodeCount: anime.episodes")

home='lib/screens/home_screen.dart'
replace(home,"  String _genre = '';\n", "  String _genre = '';\n  String _category = ''; // '' | anime | western | adult | other\n")
replace(home,"      _genre.isNotEmpty ||\n", "      _genre.isNotEmpty ||\n      _category.isNotEmpty ||\n")
replace(home,"    if (_collection.isNotEmpty) {\n", """    if (_category.isNotEmpty) {
      items = items.where((a) => a.category == _category).toList();
    }
    if (_collection.isNotEmpty) {
""")
replace(home,"                _sortChip(),\n", """                _sortChip(),
                const SizedBox(width: 8),
                for (final c in const [
                  ['', 'Toutes animations'],
                  ['anime', 'Animés japonais'],
                  ['western', 'Dessins animés'],
                  ['adult', 'Animation adulte'],
                  ['other', 'Autres animations'],
                ]) ...[
                  _chip(
                    label: c[1],
                    selected: _category == c[0],
                    onTap: () => setState(() => _category = c[0]),
                  ),
                  const SizedBox(width: 8),
                ],
""")

detail='lib/screens/detail_screen.dart'
replace(detail,"import 'package:cached_network_image/cached_network_image.dart';\n", "import 'dart:io';\n\nimport 'package:cached_network_image/cached_network_image.dart';\n")
replace(detail,"  bool _showOriginal = false;\n", "  bool _showOriginal = false;\n  bool _immersiveBackground = true;\n")
replace(detail,"""    final results = await MetadataService.searchMany(
      query,
      source: library.settings.metaSource,
    );""", """    final results = await MetadataService.searchMany(
      query,
      source: (anime.category == 'western' || anime.category == 'adult')
          ? 'tmdb' : library.settings.metaSource,
      tmdbKey: library.settings.tmdbKey,
    );""")
replace(detail,"  /// Les trois écritures du titre, quand elles sont connues.\n", """  Widget _backgroundArt() {
    final path = anime.posterPath;
    final remote = anime.imageUrl;
    Widget image;
    if (path != null && File(path).existsSync()) {
      image = Image.file(File(path), fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (remote != null && remote.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: remote, fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      image = const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        image,
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0x8C000000), Palette.ink.withValues(alpha: 0.82),
                   Palette.ink.withValues(alpha: 0.93)],
          stops: const [0.0, 0.45, 1.0],
        ))),
      ]),
    );
  }

  /// Les trois écritures du titre, quand elles sont connues.
""")
# Flutter 3.24 compatibility: withOpacity rather than withValues
p=root/detail
s=p.read_text(encoding='utf-8').replace('Palette.ink.withValues(alpha: 0.82)', 'Palette.ink.withOpacity(0.82)').replace('Palette.ink.withValues(alpha: 0.93)', 'Palette.ink.withOpacity(0.93)')
p.write_text(s,encoding='utf-8')
replace(detail,"        return Scaffold(\n          body: ScrollConfiguration(", """        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_immersiveBackground) _backgroundArt(),
              ScrollConfiguration(""")
replace(detail,"          ),\n        );\n      },\n    );\n  }\n\n  // ---------------------------------------------------------------- bandeau", """              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- bandeau""")
replace(detail,"                          OutlinedButton.icon(\n                            onPressed: _working ? null : _searchAgain,", """                          OutlinedButton.icon(
                            onPressed: () => setState(() =>
                                _immersiveBackground = !_immersiveBackground),
                            icon: Icon(_immersiveBackground
                                ? Icons.wallpaper_outlined : Icons.image_outlined,
                                size: 18),
                            label: Text(_immersiveBackground
                                ? 'Fond classique' : 'Image plein écran'),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Catégorie',
                            onSelected: (value) async {
                              anime.category = value;
                              await library.save();
                              library.refresh();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'anime', child: Text('Animé japonais')),
                              PopupMenuItem(value: 'western', child: Text('Dessin animé')),
                              PopupMenuItem(value: 'adult', child: Text('Animation adulte')),
                              PopupMenuItem(value: 'other', child: Text('Autre animation')),
                            ],
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.category_outlined, size: 18),
                              label: const Text('Catégorie'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _working ? null : _searchAgain,""")
# make the foreground buttons consistently visible; avoid disabled button inside popup
p=root/detail;s=p.read_text(encoding='utf-8').replace("child: OutlinedButton.icon(\n                              onPressed: null,\n                              icon: const Icon(Icons.category_outlined, size: 18),\n                              label: const Text('Catégorie'),\n                            ),", "child: Padding(\n                              padding: const EdgeInsets.all(10),\n                              child: Row(mainAxisSize: MainAxisSize.min, children: [\n                                Icon(Icons.category_outlined, size: 18, color: Palette.kin),\n                                const SizedBox(width: 6),\n                                Text('Catégorie', style: TextStyle(color: Palette.text)),\n                              ]),\n                            ),")
p.write_text(s,encoding='utf-8')
print('Correctif terminé. Vérifier avec flutter analyze puis flutter build.')
