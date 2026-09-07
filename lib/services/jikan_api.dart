import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/anime_meta.dart';

export '../models/anime_meta.dart';

/// Jikan (API publique de MyAnimeList), utilisee en secours d'AniList.
/// Ses limites sont strictes : 3 requetes par seconde et 60 par minute.
/// Le regulateur ci-dessous tient une fenetre glissante des derniers appels
/// plutot qu'un simple delai fixe, et respecte l'en-tete Retry-After.
class JikanApi {
  static const String _base = 'https://api.jikan.moe/v4';

  static const int _maxPerSecond = 3;
  static const int _maxPerMinute = 60;
  static const int _minGapMs = 380;

  static final List<DateTime> _calls = [];

  static Future<void> _gate() async {
    while (true) {
      final now = DateTime.now();
      _calls.removeWhere((t) => now.difference(t).inMilliseconds > 60000);

      final inLastSecond =
          _calls.where((t) => now.difference(t).inMilliseconds < 1000).toList();
      var waitMs = 0;

      if (_calls.isNotEmpty) {
        final sinceLast = now.difference(_calls.last).inMilliseconds;
        if (sinceLast < _minGapMs) waitMs = _minGapMs - sinceLast;
      }
      if (inLastSecond.length >= _maxPerSecond) {
        final w = 1000 - now.difference(inLastSecond.first).inMilliseconds + 5;
        if (w > waitMs) waitMs = w;
      }
      if (_calls.length >= _maxPerMinute) {
        final w = 60000 - now.difference(_calls.first).inMilliseconds + 5;
        if (w > waitMs) waitMs = w;
      }

      if (waitMs <= 0) {
        _calls.add(DateTime.now());
        return;
      }
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  }

  static Future<AnimeMeta?> search(String title) async {
    final list = await searchMany(title, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  static Future<List<AnimeMeta>> searchMany(String title, {int limit = 8}) async {
    final query = title.trim();
    if (query.isEmpty) return const [];

    for (var attempt = 0; attempt < 4; attempt++) {
      await _gate();
      try {
        final uri = Uri.parse(
          '$_base/anime?q=${Uri.encodeQueryComponent(query)}'
          '&limit=$limit&sfw=true&order_by=members&sort=desc',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 20));

        if (res.statusCode == 429) {
          final retry = double.tryParse(res.headers['retry-after'] ?? '') ?? 2;
          await Future<void>.delayed(
              Duration(milliseconds: (retry * 1000).round() + attempt * 500));
          continue;
        }
        if (res.statusCode != 200) return const [];

        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = body['data'] as List? ?? const [];
        return data
            .map((e) => _map(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const [];
  }

  static AnimeMeta _map(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final jpg = images?['jpg'] as Map<String, dynamic>?;
    final webp = images?['webp'] as Map<String, dynamic>?;

    final genres = <String>[];
    for (final field in ['genres', 'themes', 'demographics']) {
      for (final g in j[field] as List? ?? const []) {
        final name = (g as Map)['name']?.toString();
        if (name != null && name != 'Hentai' && !genres.contains(name)) {
          genres.add(name);
        }
      }
    }

    final studios = (j['studios'] as List? ?? const [])
        .map((s) => (s as Map)['name']?.toString())
        .whereType<String>()
        .toList();

    final english = j['title_english'] as String?;

    return AnimeMeta(
      sourceId: j['mal_id'] as int?,
      source: 'jikan',
      title: (english != null && english.trim().isNotEmpty)
          ? english
          : (j['title'] as String? ?? 'Sans titre'),
      titleNative: j['title_japanese'] as String?,
      imageUrl: (webp?['large_image_url'] ??
          jpg?['large_image_url'] ??
          jpg?['image_url']) as String?,
      synopsis: j['synopsis'] as String?,
      genres: genres,
      score: (j['score'] as num?)?.toDouble(),
      popularity: j['members'] as int?,
      year: j['year'] as int? ??
          int.tryParse(
            ((j['aired'] as Map?)?['from'] as String? ?? '').split('-').first,
          ),
      type: j['type'] as String?,
      status: j['status'] as String?,
      episodes: j['episodes'] as int?,
      studios: studios.isEmpty ? null : studios.join(', '),
    );
  }
}
