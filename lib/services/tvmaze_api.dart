import 'dart:convert';

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
            .replaceAll(RegExp(r'\s+'), ' ').trim();
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
