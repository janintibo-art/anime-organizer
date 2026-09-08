import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime_meta.dart';
import 'http_client.dart';

/// Troisième source, indépendante d'AniList et de MyAnimeList.
/// Gratuite, sans clé. Sert de filet quand les deux autres tombent.
class KitsuApi {
  /// Kitsu a changé de domaine : on essaie les deux.
  static const List<String> _hosts = ['kitsu.app', 'kitsu.io'];
  static String? lastError;

  static Future<Map<String, dynamic>?> _get(String path, Map<String, String> params) async {
    for (final host in _hosts) {
      try {
        final uri = Uri.https(host, '/api/edge/$path', params);
        final res = await http
            .get(uri, headers: AppHttp.headers(accept: 'application/vnd.api+json'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode} ($host)';
          continue;
        }
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (e) {
        lastError = e.toString();
      }
    }
    return null;
  }

  static Future<List<AnimeMeta>> search(String title, {int limit = 8}) async {
    if (title.trim().isEmpty) return const [];
    final body = await _get('anime', {
      'filter[text]': title.trim(),
      'page[limit]': '$limit',
      'include': 'categories',
    });
    return _parse(body);
  }

  static const Map<String, String> _sortFields = {
    'TRENDING_DESC': '-userCount',
    'POPULARITY_DESC': '-userCount',
    'SCORE_DESC': '-averageRating',
    'START_DATE_DESC': '-startDate',
    'FAVOURITES_DESC': '-favoritesCount',
  };

  static Future<List<AnimeMeta>> browse({
    int page = 1,
    int perPage = 20,
    String sort = 'TRENDING_DESC',
    String? genre,
    String? format,
  }) async {
    final params = <String, String>{
      'page[limit]': '$perPage',
      'page[offset]': '${(page - 1) * perPage}',
      'sort': _sortFields[sort] ?? '-userCount',
      'include': 'categories',
      if (format != null && format.isNotEmpty)
        'filter[subtype]': format.toLowerCase(),
      if (genre != null && genre.isNotEmpty)
        'filter[categories]': genre.toLowerCase().replaceAll(' ', '-'),
    };
    final body = await _get('anime', params);
    return _parse(body);
  }

  static List<AnimeMeta> _parse(Map<String, dynamic>? body) {
    if (body == null) return const [];
    final data = body['data'] as List? ?? const [];
    return data
        .map((e) => _map(Map<String, dynamic>.from(e as Map)))
        .whereType<AnimeMeta>()
        .toList();
  }

  static AnimeMeta? _map(Map<String, dynamic> item) {
    final attrs = item['attributes'] as Map<String, dynamic>?;
    if (attrs == null) return null;

    final titles = attrs['titles'] as Map<String, dynamic>? ?? const {};
    final english = (titles['en'] ?? titles['en_us'])?.toString();
    final romaji = (titles['en_jp'] ?? attrs['canonicalTitle'])?.toString();
    final native = titles['ja_jp']?.toString();
    final name = (english != null && english.trim().isNotEmpty)
        ? english
        : (romaji ?? attrs['canonicalTitle']?.toString());
    if (name == null || name.trim().isEmpty) return null;

    final poster = attrs['posterImage'] as Map<String, dynamic>?;
    final rating = double.tryParse(attrs['averageRating']?.toString() ?? '');
    final start = attrs['startDate']?.toString();

    return AnimeMeta(
      sourceId: int.tryParse(item['id']?.toString() ?? ''),
      source: 'kitsu',
      title: name,
      titleRomaji: romaji,
      titleNative: native,
      imageUrl: (poster?['large'] ?? poster?['medium'] ?? poster?['original'])
          as String?,
      synopsis: attrs['synopsis']?.toString(),
      score: rating == null ? null : rating / 10.0,
      popularity: attrs['userCount'] as int?,
      year: start == null || start.length < 4
          ? null
          : int.tryParse(start.substring(0, 4)),
      type: attrs['subtype']?.toString(),
      status: attrs['status']?.toString(),
      episodes: attrs['episodeCount'] as int?,
    );
  }
}
