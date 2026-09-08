import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime_meta.dart';
import 'http_client.dart';

/// TMDB : demande une clé gratuite, mais apporte quelque chose qu'aucune
/// autre source ne donne — le synopsis et le titre **directement en français**,
/// sans passer par un service de traduction.
class TmdbApi {
  static const String _host = 'api.themoviedb.org';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';

  /// Mot-clé « anime » du catalogue TMDB, pour ne pas ramener toute la télé.
  static const String _animeKeyword = '210024';

  static String? lastError;
  static Map<int, String> _genres = {};

  static Future<Map<String, dynamic>?> _get(
    String path,
    String apiKey,
    Map<String, String> params,
  ) async {
    if (apiKey.trim().isEmpty) {
      lastError = 'Aucune clé TMDB renseignée.';
      return null;
    }
    try {
      final uri = Uri.https(_host, path, {
        'api_key': apiKey.trim(),
        'language': 'fr-FR',
        ...params,
      });
      final res = await http
          .get(uri, headers: AppHttp.headers())
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}';
        return null;
      }
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  static Future<void> _ensureGenres(String apiKey) async {
    if (_genres.isNotEmpty) return;
    final body = await _get('/3/genre/tv/list', apiKey, const {});
    final list = body?['genres'] as List? ?? const [];
    _genres = {
      for (final g in list)
        (g as Map)['id'] as int: g['name']?.toString() ?? '',
    };
  }

  static Future<List<AnimeMeta>> search(
    String title,
    String apiKey, {
    int limit = 8,
  }) async {
    if (title.trim().isEmpty) return const [];
    await _ensureGenres(apiKey);
    final body = await _get('/3/search/tv', apiKey, {
      'query': title.trim(),
      'include_adult': 'false',
    });
    return _parse(body, limit);
  }

  static const Map<String, String> _sorts = {
    'TRENDING_DESC': 'popularity.desc',
    'POPULARITY_DESC': 'popularity.desc',
    'SCORE_DESC': 'vote_average.desc',
    'START_DATE_DESC': 'first_air_date.desc',
    'FAVOURITES_DESC': 'vote_count.desc',
  };

  static Future<List<AnimeMeta>> browse(
    String apiKey, {
    int page = 1,
    String sort = 'TRENDING_DESC',
  }) async {
    await _ensureGenres(apiKey);
    final body = await _get('/3/discover/tv', apiKey, {
      'with_keywords': _animeKeyword,
      'sort_by': _sorts[sort] ?? 'popularity.desc',
      'page': '$page',
      'include_adult': 'false',
      'vote_count.gte': '20',
    });
    return _parse(body, 40);
  }

  static List<AnimeMeta> _parse(Map<String, dynamic>? body, int limit) {
    if (body == null) return const [];
    final results = body['results'] as List? ?? const [];
    return results
        .take(limit)
        .map((e) => _map(Map<String, dynamic>.from(e as Map)))
        .whereType<AnimeMeta>()
        .toList();
  }

  static AnimeMeta? _map(Map<String, dynamic> item) {
    final name = item['name']?.toString();
    if (name == null || name.trim().isEmpty) return null;

    final poster = item['poster_path']?.toString();
    final date = item['first_air_date']?.toString();
    final vote = (item['vote_average'] as num?)?.toDouble();
    final genreIds = (item['genre_ids'] as List? ?? const [])
        .map((e) => _genres[e as int])
        .whereType<String>()
        .where((g) => g.isNotEmpty)
        .toList();

    return AnimeMeta(
      sourceId: item['id'] as int?,
      source: 'tmdb',
      title: name,
      titleRomaji: item['original_name']?.toString(),
      imageUrl: poster == null || poster.isEmpty ? null : '$_imageBase$poster',
      synopsis: item['overview']?.toString(),
      genres: genreIds,
      score: vote == null || vote == 0 ? null : vote,
      popularity: (item['popularity'] as num?)?.round(),
      year: date == null || date.length < 4
          ? null
          : int.tryParse(date.substring(0, 4)),
      type: 'TV',
    );
  }
}
