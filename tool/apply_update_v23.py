#!/usr/bin/env python3
"""Anime Organizer V23: source-aware animation categorisation and film matching.
Transactional: all anchors validated before changing files. Safe to rerun.
"""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
M=ROOT/'lib/models/anime_meta.dart'
T=ROOT/'lib/services/tmdb_api.dart'
S=ROOT/'lib/services/scanner.dart'
C=ROOT/'lib/services/library_controller.dart'
D=ROOT/'lib/screens/detail_screen.dart'
files=[M,T,S,C,D]
MARK='// V23_AUTO_CATEGORY'
if all(MARK in p.read_text(encoding='utf-8') for p in files):
    print('V23 déjà appliquée.');sys.exit(0)
data={p:p.read_text(encoding='utf-8') for p in files}
def replace(p,old,new):
    s=data[p]
    if MARK in s:
        return
    n=s.count(old)
    if n!=1: raise RuntimeError(f'{p.relative_to(ROOT)} : ancrage attendu une fois, trouvé {n}: {old[:70]!r}')
    data[p]=s.replace(old,new,1)

# Add source origin to common metadata, with a default for existing providers.
replace(M,"  final String title;\n", "  final String title;\n  // V23_AUTO_CATEGORY: origin, if actually supplied by a metadata provider.\n  final String? originLanguage;\n")
replace(M,"    required this.title,\n", "    required this.title,\n    this.originLanguage,\n")
replace(M,"        'title': title,\n", "        'title': title,\n        'originLanguage': originLanguage,\n")
replace(M,"        title: j['title'] as String? ?? 'Sans titre',\n", "        title: j['title'] as String? ?? 'Sans titre',\n        originLanguage: j['originLanguage'] as String?,\n")

# TMDB: include animated films, preserve film/TV identity and original language.
replace(T,"  static List<AnimeMeta> _parse(Map<String, dynamic>? body, int limit) {", '''  // V23_AUTO_CATEGORY: feature films are NOT in /search/tv.
  // Only request film results explicitly tagged Animation (genre 16).
  static Future<List<AnimeMeta>> searchAnimatedMovies(
      String title, String apiKey, {int limit = 8}) async {
    if (apiKey.trim().isEmpty || title.trim().isEmpty) return const [];
    final body = await _get('/3/search/movie', apiKey, {
      'query': title.trim(), 'include_adult': 'true',
    });
    if (body == null) return const [];
    final results = (body['results'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => (m['genre_ids'] as List? ?? const []).contains(16))
        .take(limit);
    return results.map((item) {
      final poster = item['poster_path']?.toString();
      final date = item['release_date']?.toString();
      return AnimeMeta(
        source: 'tmdb_movie', sourceId: item['id'] as int?,
        title: (item['title'] ?? item['original_title'] ?? '').toString(),
        titleRomaji: item['original_title']?.toString(),
        originLanguage: item['original_language']?.toString(),
        imageUrl: poster == null || poster.isEmpty ? null : '$_imageBase$poster',
        synopsis: item['overview']?.toString(), genres: const ['Animation'],
        score: (item['vote_average'] as num?)?.toDouble(),
        popularity: (item['popularity'] as num?)?.round(),
        year: date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4)),
        type: 'MOVIE', episodes: 1,
      );
    }).where((m) => m.title.isNotEmpty).toList();
  }

  static List<AnimeMeta> _parse(Map<String, dynamic>? body, int limit) {''')
replace(T,"      source: 'tmdb',\n      title: name,", "      source: 'tmdb',\n      originLanguage: item['original_language']?.toString(),\n      title: name,")

# Single-file titles and folder names are valid evidence, no episode marker required.
replace(S,"  /// Tri naturel : « Episode 2 » avant « Episode 10 ».\n", '''  // V23_AUTO_CATEGORY: a movie or isolated video need not be S01E01.
  static String? identificationTitle(List<Episode> episodes, String folderTitle) {
    final consensus = titleFromFiles(episodes);
    if (consensus != null) return consensus;
    if (episodes.length == 1) {
      final raw = p.basenameWithoutExtension(episodes.single.path);
      final title = cleanTitle(raw).replaceAll(RegExp(r'[._]+'), ' ').trim();
      if (title.length >= 4) return title;
    }
    final folder = cleanTitle(folderTitle);
    return folder.trim().length >= 4 ? folder.trim() : null;
  }

  /// Tri naturel : « Episode 2 » avant « Episode 10 ».\n''')

# Metadata category inferred from verified provider, not popularity or unrelated synopsis.
replace(C,"  static String _guessCategory(String title) {", '''  // V23_AUTO_CATEGORY: only strong evidence sets a category.
  static String _categoryFromMeta(AnimeMeta meta, String original) {
    final t = MetadataService.stripAccents('$original ${meta.title}');
    if (RegExp(r'\\b(fritz (le chat|the cat)|south park|beavis|rick and morty|'
        r'family guy|american dad|bojack horseman|big mouth|solar opposites)\\b')
        .hasMatch(t)) return 'adult';
    if (meta.source == 'tvmaze') return 'western';
    if (meta.source == 'tmdb' || meta.source == 'tmdb_movie') {
      if (meta.originLanguage == 'ja') return 'anime';
      if (meta.originLanguage != null && meta.originLanguage!.isNotEmpty) return 'western';
    }
    return _guessCategory(original);
  }

  static String _guessCategory(String title) {''')
replace(C,"    final t = MetadataService.stripAccents(title);\n    if (RegExp(r'\\b(beavis", "    final t = MetadataService.stripAccents(title);\n    if (RegExp(r'\\b(fritz (le chat|the cat)|beavis")
replace(C,"    final isWestern = anime.category == 'western' || anime.category == 'adult';\n", '''    // V23_AUTO_CATEGORY: use filename for uncertain items, not stale DBZ.
    final titleEvidence = Scanner.identificationTitle(anime.episodes, anime.folderTitle) ?? query;
    final inferredCategory = _guessCategory(titleEvidence);
    if (overrideQuery == null && inferredCategory != 'anime' &&
        !manualIds.contains(anime.id)) anime.category = inferredCategory;
    final isWestern = anime.category == 'western' || anime.category == 'adult';
''')
replace(C,"    final fileTitle = Scanner.titleFromFiles(anime.episodes);\n    final count", "    final fileTitle = Scanner.identificationTitle(anime.episodes, anime.folderTitle);\n    final count")
replace(C,"      applyMeta(anime, meta);\n      remember(anime.folderTitle, meta.titleRomaji ?? meta.title);", '''      applyMeta(anime, meta);
      if (!manualIds.contains(anime.id)) anime.category = _categoryFromMeta(meta, fileTitle ?? query);
      remember(anime.folderTitle, meta.titleRomaji ?? meta.title);''')
replace(C,"    anime.malId = meta.sourceId;\n    anime.metaSource = meta.source;", '''    // V23_AUTO_CATEGORY: a trusted manual choice may still override this later.
    anime.category = _categoryFromMeta(meta, anime.folderTitle);
    anime.malId = meta.sourceId;
    anime.metaSource = meta.source;''')

# Existing wrong matches: include 1-file movies where known title clearly disagrees.
replace(C,"        final file = Scanner.titleFromFiles(a.episodes);\n", "        final file = Scanner.identificationTitle(a.episodes, a.folderTitle);\n")
replace(C,"        final file = Scanner.titleFromFiles(anime.episodes)!;\n", "        final file = Scanner.identificationTitle(anime.episodes, anime.folderTitle)!;\n")
replace(C,"        final category = _guessCategory(file);\n        final isWestern", "        final category = _guessCategory(file);\n        final isWestern")
replace(C,"        final source = isWestern ? 'western' : settings.metaSource;\n", "        final source = 'animation';\n")
replace(C,"        if (category != 'anime') anime.category = category;\n        remember", "        anime.category = _categoryFromMeta(match, file);\n        remember")
replace(C,"          _clearWrongMetadata(anime, file);\n          lastScanUnresolved++;", "          _clearWrongMetadata(anime, file);\n          anime.category = category;\n          lastScanUnresolved++;")

# Multi-provider search for unknown category including animated films.
replace(C,"    final preferredSource = isWestern\n        ? 'western'\n        : settings.metaSource;", '''    final preferredSource = 'animation';''')
# Allow clearing stale metadata on single-file matching failure without clobbering viewed positions:
replace(C,"    if (meta == null) {\n      // Une panne reseau", '''    if (meta == null && overrideQuery == null && !manualIds.contains(anime.id)) {
      // Do not assign a random popular result; keep the filename as the title.
      if (anime.metaFetched && fileTitle != null &&
          MetadataService.similarity(fileTitle, anime.apiTitle ?? '') < 0.48) {
        _clearWrongMetadata(anime, fileTitle);
      }
    }
    if (meta == null) {
      // Une panne reseau''')

# UI manual correction: search from all animation sources, incl movies.
replace(D,"      source: western ? 'western' : library.settings.metaSource,", "      source: 'animation',")
replace(D,"        : await MetadataService.searchMany(query, source: 'western',", "        : await MetadataService.searchMany(query, source: 'western',")
# Add marker to detail via existing anchor comment to support idempotence.
replace(D,"    // Si la catégorie a été mal détectée, la correction doit aussi", "    // V23_AUTO_CATEGORY: matching searches all catalogs, including animated films.\n    // Si la catégorie a été mal détectée, la correction doit aussi")

# The new cross-catalog search: avoid accepting unrelated candidates.
P=ROOT/'lib/services/metadata_service.dart'
data[P]=P.read_text(encoding='utf-8')
replace(P,"    switch (source) {\n", '''    // V23_AUTO_CATEGORY: conservative animated-film and TV cross-search.
    if (source == 'animation') {
      final out = <AnimeMeta>[];
      if (tmdbKey.trim().isNotEmpty) {
        out.addAll(await TmdbApi.search(title, tmdbKey, limit: limit));
        out.addAll(await TmdbApi.searchAnimatedMovies(title, tmdbKey, limit: limit));
      }
      out.addAll(await TvmazeApi.search(title, limit: limit));
      // Japanese results are considered too, even for unknown categories.
      out.addAll(await AniListApi.searchMany(title, limit: limit));
      final dedup = <String>{};
      final results = out.where((m) => dedup.add('${m.source}:${m.sourceId ?? m.title}'))
          .toList()
        ..sort((a,b) => score(b, title, null).compareTo(score(a, title, null)));
      return results.take(limit).toList();
    }
    switch (source) {
''')
# Source-aware score filtering in smart search already rejects weak titles.

# Validate all before committing; if user modified an anchor, refuse and don't partially patch.
for p,c in data.items():
    if MARK not in c: raise RuntimeError(f'Marqueur manquant: {p.relative_to(ROOT)}')
for p,c in data.items():
    if p.read_text(encoding='utf-8') != c:
        p.write_text(c, encoding='utf-8')
print('V23 appliquée : recherche films animés, catégories automatiques, réparation 1 fichier.')
