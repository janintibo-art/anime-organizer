import 'dart:math';

import '../models/anime_meta.dart';
import 'anilist_api.dart';
import 'jikan_api.dart';
import 'animethemes_api.dart';
import 'kitsu_api.dart';
import 'tmdb_api.dart';
import 'tvmaze_api.dart';

/// Choisit la source de metadonnees.
/// En mode automatique : AniList d'abord (rapide et complet), Jikan en
/// secours quand AniList ne trouve rien.
class MetadataService {
  // V47_QUALITY_CACHE : memorisation temporaire des memes requetes.
  // Le score et les seuils de validation restent inchanges.
  static final Map<String, Future<List<AnimeMeta>>> _searchCache = {};
  static const int _maxCachedSearches = 160;
  static final RegExp _accents = RegExp('[\u00C0-\u017F]');

  static const Map<String, String> _accentMap = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };

  static String stripAccents(String input) {
    final buffer = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      buffer.write(_accentMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  /// Un titre francais ne correspond a rien dans les bases japonaises :
  /// on le detecte pour tenter une traduction avant la recherche.
  static bool looksFrench(String title) {
    if (_accents.hasMatch(title)) return true;
    const words = [
      'les', 'des', 'une', 'dans', 'avec', 'pour', 'sont', 'seront',
      'mon', 'ma', 'mes', 'du', 'au', 'aux', 'chez', 'plus', 'tout',
    ];
    final lower = ' ${title.toLowerCase()} ';
    return words.any((w) => lower.contains(' $w '));
  }

  /// Variantes de recherche, de la plus fidele a la plus large.
  static List<String> variants(String title) {
    final out = <String>[];
    void add(String value) {
      final v = value.trim().replaceAll(RegExp(r'\s{2,}'), ' ');
      if (v.length > 2 && !out.contains(v)) out.add(v);
    }

    add(title);
    final plain = stripAccents(title);
    add(plain);
    add(plain.replaceAll(
        RegExp(r"^(les|le|la|l'|the|un|une)\s+", caseSensitive: false), ''));
    final words = plain.split(RegExp(r'\s+'));
    if (words.length > 3) add(words.take(3).join(' '));
    return out.take(4).toList();
  }

  // ------------------------------------------------------- choix du candidat

  static String _normalize(String input) {
    final plain = stripAccents(input).toLowerCase();
    return plain.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(
        RegExp(r'\s+'), ' ').trim();
  }

  /// Similarite de Dice sur les paires de lettres : tolerante aux fautes
  /// de frappe et aux mots en plus, contrairement a une egalite stricte.
  static double similarity(String a, String b) {
    final x = _normalize(a);
    final y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.contains(y) || y.contains(x)) return 0.9;

    Set<String> bigrams(String s) {
      final out = <String>{};
      for (var i = 0; i < s.length - 1; i++) {
        out.add(s.substring(i, i + 2));
      }
      return out;
    }

    final bx = bigrams(x);
    final by = bigrams(y);
    if (bx.isEmpty || by.isEmpty) return 0;
    final common = bx.intersection(by).length;
    return 2 * common / (bx.length + by.length);
  }

  /// Note un candidat : ressemblance du titre, nombre d'episodes coherent,
  /// et penalite pour un film propose face a une serie de fichiers.
  static double score(AnimeMeta meta, String query, int? fileCount) {
    var best = similarity(query, meta.title);
    if (meta.titleRomaji != null) {
      best = max(best, similarity(query, meta.titleRomaji!));
    }
    if (meta.titleNative != null) {
      best = max(best, similarity(query, meta.titleNative!));
    }

    var total = best * 100;

    final episodes = meta.episodes;
    if (fileCount != null && fileCount > 0 && episodes != null && episodes > 0) {
      final diff = (episodes - fileCount).abs();
      if (diff == 0) {
        total += 25;
      } else if (diff <= 2) {
        total += 12;
      } else if (diff > 12) {
        total -= 12;
      }
    }

    final type = (meta.type ?? '').toUpperCase();
    if (fileCount != null && fileCount > 3 && type == 'MOVIE') total -= 25;
    if (fileCount == 1 && (type == 'TV' || type == 'ONA')) total -= 8;

    if (meta.popularity != null) {
      total += min(meta.popularity! / 40000, 5);
    }
    return total;
  }

  /// Essaie plusieurs formulations, note tous les candidats et garde
  /// le meilleur. Renvoie null si aucun ne ressemble vraiment au titre.
  static Future<AnimeMeta?> smartSearch(
    String title, {
    String source = 'auto',
    int? episodeCount,
    String tmdbKey = '',
  }) async {
    AnimeMeta? best;
    var bestScore = 0.0;
    var bestSimilarity = 0.0;

    for (final query in variants(title)) {
      final results =
          await searchMany(query, source: source, limit: 8, tmdbKey: tmdbKey);
      for (final candidate in results) {
        final value = score(candidate, query, episodeCount);
        final sim = max(
          similarity(query, candidate.title),
          candidate.titleRomaji == null
              ? 0.0
              : similarity(query, candidate.titleRomaji!),
        );
        if (value > bestScore) {
          bestScore = value;
          bestSimilarity = sim;
          best = candidate;
        }
      }
      // Une correspondance franche sur la premiere formulation suffit.
      if (bestSimilarity >= 0.75) return best;
    }

    // Seuil conservateur : un titre peu ressemblant est une fiche fausse,
    // pas une identification réussie. Une recherche manuelle reste possible.
    return bestSimilarity >= 0.62 ? best : null;
  }

  static Future<AnimeMeta?> search(
    String title, {
    String source = 'auto',
    String tmdbKey = '',
  }) async {
    final results =
        await searchMany(title, source: source, limit: 1, tmdbKey: tmdbKey);
    return results.isEmpty ? null : results.first;
  }

  static Future<List<AnimeMeta>> searchMany(
    String title, {
    String source = 'auto',
    int limit = 8,
    String tmdbKey = '',
  }) async {
    // Un meme titre recherche par le scan, le titre du fichier ou l'IA
    // ne doit pas relancer une serie d'appels reseau identiques.
    final key = '$source\u001f${title.trim().toLowerCase()}\u001f$limit\u001f$tmdbKey';
    final cached = _searchCache[key];
    if (cached != null) return await cached;
    final request = _searchManyUncached(title,
        source: source, limit: limit, tmdbKey: tmdbKey);
    _searchCache[key] = request;
    if (_searchCache.length > _maxCachedSearches) {
      _searchCache.remove(_searchCache.keys.first);
    }
    try {
      final result = await request;
      // Ne jamais memoriser un echec de recherche : une API peut etre
      // temporairement indisponible ou limiter le nombre de requetes.
      if (result.isEmpty && identical(_searchCache[key], request)) {
        _searchCache.remove(key);
      }
      return result;
    } catch (_) {
      // Une panne de reseau ne doit jamais etre conservee dans le cache.
      if (identical(_searchCache[key], request)) _searchCache.remove(key);
      rethrow;
    }
  }

  static Future<List<AnimeMeta>> _searchManyUncached(
    String title, {
    String source = 'auto',
    int limit = 8,
    String tmdbKey = '',
  }) async {
    // V23_AUTO_CATEGORY: conservative animated-film and TV cross-search.
    if (source == 'animation') {
      final out = <AnimeMeta>[];
      // Catalogues independants : lancement simultane, puis meme classement.
      // Une source moins precise ne remplace pas un meilleur candidat.
      final futures = <Future<List<AnimeMeta>>>[];
      if (tmdbKey.trim().isNotEmpty) {
        futures.add(TmdbApi.search(title, tmdbKey, limit: limit));
        futures.add(TmdbApi.searchAnimatedMovies(title, tmdbKey, limit: limit));
      }
      futures.add(TvmazeApi.search(title, limit: limit));
      futures.add(AniListApi.searchMany(title, limit: limit));
      for (final results in await Future.wait(futures)) {
        out.addAll(results);
      }
      final dedup = <String>{};
      final results = out.where((m) => dedup.add('${m.source}:${m.sourceId ?? m.title}'))
          .toList()
        ..sort((a,b) => score(b, title, null).compareTo(score(a, title, null)));
      return results.take(limit).toList();
    }
    switch (source) {
      case 'anilist':
        return AniListApi.searchMany(title, limit: limit);
      case 'jikan':
        return JikanApi.searchMany(title, limit: limit);
      case 'kitsu':
        return KitsuApi.search(title, limit: limit);
      case 'animethemes':
        return AnimeThemesApi.search(title, limit: limit);
      case 'tmdb':
        return TmdbApi.search(title, tmdbKey, limit: limit);
      case 'tvmaze':
        return TvmazeApi.search(title, limit: limit);
      case 'western':
        // TVmaze sans clé + TMDB avec clé : deux chances de trouver
        // les séries animées occidentales, sans doublons.
        if (tmdbKey.trim().isEmpty) {
          return TvmazeApi.search(title, limit: limit);
        }
        final results = await Future.wait<List<AnimeMeta>>([
          TvmazeApi.search(title, limit: limit),
          TmdbApi.search(title, tmdbKey, limit: limit),
        ]);
        final tv = results[0];
        final tmdb = results[1];
        final seen = <String>{};
        final merged = <AnimeMeta>[];
        for (final item in [...tmdb, ...tv]) {
          final key = stripAccents(item.title)
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (seen.add(key)) merged.add(item);
        }
        merged.sort((a, b) => similarity(title, b.title)
            .compareTo(similarity(title, a.title)));
        return merged.take(limit).toList();
      default:
        // Trois sources d'affilee : si AniList est coupe et MyAnimeList
        // surcharge, Kitsu prend le relais.
        final primary = await AniListApi.searchMany(title, limit: limit);
        if (primary.isNotEmpty) return primary;
        // AniList a priorite ; si elle n'a rien, interroger les trois
        // sources secondaires ensemble et conserver leur ordre de priorite.
        final backups = await Future.wait<List<AnimeMeta>>([
          JikanApi.searchMany(title, limit: limit),
          KitsuApi.search(title, limit: limit),
          AnimeThemesApi.search(title, limit: limit),
        ]);
        for (final candidates in backups) {
          if (candidates.isNotEmpty) return candidates;
        }
        if (tmdbKey.trim().isEmpty) return const [];
        return TmdbApi.search(title, tmdbKey, limit: limit);
    }
  }
}
