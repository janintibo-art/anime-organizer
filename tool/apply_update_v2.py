#!/usr/bin/env python3
"""V2: improve file-based matching, conservative repair and TVmaze support."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
if not (root/'lib/services/library_controller.dart').exists():
    print('Projet absent dans',root,'; placer le ZIP dans le projet anime_organizer.');sys.exit(2)
changes={}
def patch(path, old, new, expected=1):
    p=root/path
    s=changes.get(path,p.read_text(encoding='utf-8'))
    if new in s:
        return
    count=s.count(old)
    if count!=expected: raise RuntimeError(f'{path}: motif introuvable ou ambigu ({count}): {old[:80]!r}')
    changes[path]=s.replace(old,new,expected)

scanner='lib/services/scanner.dart'
patch(scanner,"""      final candidate = cleanTitle(e.name.substring(0, m.start));
      if (candidate.length >= 4 && candidate.length <= 100) names.add(candidate);""", """      var candidate = cleanTitle(e.name.substring(0, m.start));
      // 'Mike.Judges.Beavis.and.Butt-Head.S01E01...' : le nom du
      // distributeur/auteur n'est pas le titre reconnu par les catalogues.
      candidate = candidate.replaceFirst(
          RegExp(r'^mike[ ._-]*judge[\\s._-]*s?[ ._-]+', caseSensitive: false), '');
      candidate = candidate.replaceAll(RegExp(r'[._]+'), ' ').trim();
      if (candidate.length >= 4 && candidate.length <= 100) names.add(candidate);""")

meta='lib/services/metadata_service.dart'
patch(meta,"import 'tmdb_api.dart';", "import 'tmdb_api.dart';\nimport 'tvmaze_api.dart';")
patch(meta,"""    return bestSimilarity >= 0.32 ? best : null;
""", """    // Seuil conservateur : un titre peu ressemblant est une fiche fausse,
    // pas une identification réussie. Une recherche manuelle reste possible.
    return bestSimilarity >= 0.62 ? best : null;
""")
patch(meta,"""      case 'tmdb':
        return TmdbApi.search(title, tmdbKey, limit: limit);
""", """      case 'tmdb':
        return TmdbApi.search(title, tmdbKey, limit: limit);
      case 'tvmaze':
        return TvmazeApi.search(title, limit: limit);
""")

controller='lib/services/library_controller.dart'
patch(controller,"""  Map<String, String> knownTitles = {};
""", """  Map<String, String> knownTitles = {};

  /// Corrections confirmees par l'utilisateur : jamais retouchees en masse.
  Set<String> manualIds = {};
""")
patch(controller,"""      knownTitles = ((data['knownTitles'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));
""", """      knownTitles = ((data['knownTitles'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));
      manualIds = (data['manualIds'] as List? ?? const [])
          .map((e) => e.toString()).toSet();
""")
patch(controller,"""        'knownTitles': knownTitles,
""", """        'knownTitles': knownTitles,
        'manualIds': manualIds.toList(),
""", expected=2)
patch(controller,"""    final preferredSource = (anime.category == 'western' || anime.category == 'adult')
        ? 'tmdb'
        : settings.metaSource;
""", """    // Les dessins animes occidentaux ne sont pas dans les bases de mangas.
    // TVmaze fournit une recherche sans cle lorsque TMDB n'est pas configure.
    final isWestern = anime.category == 'western' || anime.category == 'adult';
    final preferredSource = isWestern
        ? (settings.tmdbKey.trim().isNotEmpty ? 'tmdb' : 'tvmaze')
        : settings.metaSource;
""")
patch(controller,"""    if (resolved == null) {
      seed = SeedDatabase.match(anime.folderTitle, episodeCount: count);""", """    if (resolved == null && anime.category == 'anime') {
      seed = SeedDatabase.match(anime.folderTitle, episodeCount: count);""")
patch(controller,"""    var meta = await MetadataService.smartSearch(
      resolved ?? query,
""", """    // Si le nom des videos est explicite, il l'emporte sur un dossier
    // trompeur (sauf correction manuelle deja validee).
    final inferredDifferent = fileTitle != null &&
        MetadataService.similarity(fileTitle, query) < 0.58;
    final primaryQuery = (overrideQuery == null &&
            !manualIds.contains(anime.id) && inferredDifferent)
        ? fileTitle!
        : (resolved ?? query);
    var meta = await MetadataService.smartSearch(
      primaryQuery,
""")
patch(controller,"""    if (meta == null && overrideQuery == null && fileTitle != null &&
        MetadataService.similarity(fileTitle, query) < 0.95) {""", """    if (meta == null && overrideQuery == null && fileTitle != null &&
        !manualIds.contains(anime.id) &&
        MetadataService.similarity(fileTitle, primaryQuery) < 0.95) {""")
patch(controller,"""            source: settings.metaSource,
            episodeCount: count,
            tmdbKey: settings.tmdbKey,
""", """            source: preferredSource,
            episodeCount: count,
            tmdbKey: settings.tmdbKey,
""")
# Auto category from names for old entries without overriding user chosen categories
patch(controller,"""          old.episodes = item.episodes;
          old.folderTitle = item.folderTitle;
""", """          old.episodes = item.episodes;
          old.folderTitle = item.folderTitle;
          if (old.category == 'anime' && !manualIds.contains(old.id)) {
            final fileTitle = Scanner.titleFromFiles(item.episodes);
            final guessed = _guessCategory(fileTitle ?? old.folderTitle);
            if (guessed != 'anime') old.category = guessed;
          }
""")
patch(controller,"r'\\b(south park|family guy|american dad|rick and morty|'", "r'\\b(beavis and butt[- ]head|south park|family guy|american dad|rick and morty|'")
patch(controller,"""  /// Recupere image, synopsis et genres pour une serie.
""", """  /// Re-examine les fiches deja identifiees en comparant le titre avec
  /// celui qui revient dans plusieurs episodes. Ne modifie rien sans
  /// trouver une nouvelle correspondance fiable dans les catalogues.
  Future<int> repairWrongMatches() async {
    if (busy) return 0;
    busy = true;
    var repaired = 0;
    try {
      final suspicious = animes.where((a) {
        if (manualIds.contains(a.id)) return false;
        final file = Scanner.titleFromFiles(a.episodes);
        if (file == null) return false;
        if (!a.metaFetched) return true;
        final names = [a.apiTitle, a.romajiTitle, a.frenchTitle]
            .whereType<String>();
        return names.every((n) => MetadataService.similarity(file, n) < 0.48);
      }).toList();
      for (var i = 0; i < suspicious.length; i++) {
        final anime = suspicious[i];
        final file = Scanner.titleFromFiles(anime.episodes)!;
        _report('Verification ${i + 1}/${suspicious.length} : $file',
            (i + 1) / suspicious.length);
        final category = _guessCategory(file);
        final isWestern = category == 'western' || category == 'adult';
        final source = isWestern
            ? (settings.tmdbKey.trim().isEmpty ? 'tvmaze' : 'tmdb')
            : settings.metaSource;
        final match = await MetadataService.smartSearch(file,
            source: source, tmdbKey: settings.tmdbKey,
            episodeCount: anime.episodes.where((e) => !e.bonus).length);
        if (match == null ||
            MetadataService.similarity(file, match.title) < 0.72) continue;
        applyMeta(anime, match);
        if (category != 'anime') anime.category = category;
        remember(anime.folderTitle, match.titleRomaji ?? match.title);
        if (settings.offlinePosters) {
          anime.posterPath = await PosterCache.ensure(anime.id, anime.imageUrl);
        }
        repaired++;
        await save();
        notifyListeners();
      }
      await save();
      return repaired;
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Recupere image, synopsis et genres pour une serie.
""")
# Detail manual selection saved, using correct source fallback
screen='lib/screens/detail_screen.dart'
patch(screen,"""      source: (anime.category == 'western' || anime.category == 'adult')
          ? 'tmdb' : library.settings.metaSource,
""", """      source: (anime.category == 'western' || anime.category == 'adult')
          ? (library.settings.tmdbKey.trim().isEmpty ? 'tvmaze' : 'tmdb')
          : library.settings.metaSource,
""")
patch(screen,"""      library.applyMeta(anime, chosen);
      library.remember(anime.folderTitle, chosen.titleRomaji ?? chosen.title);
""", """      library.applyMeta(anime, chosen);
      library.manualIds.add(anime.id);
      library.remember(anime.folderTitle, chosen.titleRomaji ?? chosen.title);
""")
home='lib/screens/home_screen.dart'
patch(home,"""              IconButton(
                tooltip: 'Relancer le scan',
""", """              IconButton(
                tooltip: 'Verifier les fiches incoherentes',
                onPressed: library.busy ? null : () async {
                  final count = await library.repairWrongMatches();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$count fiche(s) corrigee(s) apres verification.')));
                },
                icon: const Icon(Icons.fact_check_outlined),
              ),
              IconButton(
                tooltip: 'Relancer le scan',
""")
patch('lib/models/anime_meta.dart',
      "source == 'anilist' ? 'AniList' : 'MyAnimeList',",
      "source == 'anilist' ? 'AniList' : (source == 'tvmaze' ? 'TVmaze' : (source == 'tmdb' ? 'TMDB' : 'MyAnimeList')),")
# New provider file written after all existing patch checks passed
provider=r'''import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime_meta.dart';

/// Series TV occidentales, sans cle API. Donnees: TVmaze (CC BY-SA).
class TvmazeApi {
  static Future<List<AnimeMeta>> search(String title, {int limit = 8}) async {
    if (title.trim().isEmpty) return const [];
    try {
      final uri = Uri.https('api.tvmaze.com', '/search/shows', {'q': title.trim()});
      final response = await http.get(uri, headers: {
        'User-Agent': 'AnimeOrganizer/2.0 (personal-library-app)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      final out = <AnimeMeta>[];
      for (final item in data) {
        if (out.length >= limit) break;
        if (item is! Map || item['show'] is! Map) continue;
        final show = Map<String, dynamic>.from(item['show'] as Map);
        final name = show['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final images = show['image'] is Map
            ? Map<String, dynamic>.from(show['image'] as Map)
            : <String, dynamic>{};
        final rating = show['rating'] is Map
            ? (show['rating'] as Map)['average'] as num?
            : null;
        final premiered = show['premiered']?.toString() ?? '';
        final summary = show['summary']?.toString() ?? '';
        final plain = summary
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll('&amp;', '&').replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ')
            .replaceAll(RegExp(r'\\s+'), ' ').trim();
        out.add(AnimeMeta(
          sourceId: show['id'] is int ? show['id'] as int : null,
          source: 'tvmaze',
          title: name,
          imageUrl: (images['original'] ?? images['medium'])?.toString(),
          synopsis: plain,
          genres: (show['genres'] as List? ?? const [])
              .map((e) => e.toString()).toList(),
          score: rating?.toDouble(),
          year: premiered.length >= 4 ? int.tryParse(premiered.substring(0, 4)) : null,
          type: 'TV',
          status: show['status']?.toString(),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
'''
# correct regex raw string contents in emitted Dart
provider=provider.replace("RegExp(r'\\\\s+')", "RegExp(r'\\s+')")
for path,content in changes.items():
    p=root/path
    p.write_text(content,encoding='utf-8')
    print('Modifie:',path)
(root/'lib/services/tvmaze_api.dart').write_text(provider,encoding='utf-8')
print('Ajoute: lib/services/tvmaze_api.dart')
