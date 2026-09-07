import 'dart:convert';

import 'package:http/http.dart' as http;

/// Metadonnees issues de Jikan (API publique et gratuite de MyAnimeList).
/// Aucune cle n'est necessaire. Limite : 3 requetes/seconde, 60/minute.
class JikanApi {
  static const String _base = 'https://api.jikan.moe/v4';
  static DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _throttle() async {
    final elapsed = DateTime.now().difference(_lastCall);
    const gap = Duration(milliseconds: 800);
    if (elapsed < gap) {
      await Future<void>.delayed(gap - elapsed);
    }
    _lastCall = DateTime.now();
  }

  /// Renvoie la meilleure correspondance pour un titre, ou null.
  static Future<AnimeMeta?> search(String title) async {
    final list = await searchMany(title, limit: 1);
    return list.isEmpty ? null : list.first;
  }

  /// Renvoie plusieurs correspondances (utile pour corriger un mauvais match).
  static Future<List<AnimeMeta>> searchMany(String title, {int limit = 8}) async {
    final query = title.trim();
    if (query.isEmpty) return const [];

    for (var attempt = 0; attempt < 3; attempt++) {
      await _throttle();
      try {
        final uri = Uri.parse(
          '$_base/anime?q=${Uri.encodeQueryComponent(query)}&limit=$limit&sfw=true&order_by=members&sort=desc',
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 20));

        if (res.statusCode == 429) {
          await Future<void>.delayed(Duration(seconds: 2 + attempt * 2));
          continue;
        }
        if (res.statusCode != 200) return const [];

        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = body['data'] as List? ?? const [];
        return data
            .map((e) => AnimeMeta.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: 1 + attempt));
      }
    }
    return const [];
  }
}

class AnimeMeta {
  final int? malId;
  final String title;
  final String? imageUrl;
  final String? synopsis;
  final List<String> genres;
  final double? score;
  final int? year;
  final String? type;
  final String? status;
  final int? episodes;

  const AnimeMeta({
    this.malId,
    required this.title,
    this.imageUrl,
    this.synopsis,
    this.genres = const [],
    this.score,
    this.year,
    this.type,
    this.status,
    this.episodes,
  });

  factory AnimeMeta.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final jpg = images?['jpg'] as Map<String, dynamic>?;
    final webp = images?['webp'] as Map<String, dynamic>?;

    final genres = <String>[];
    for (final field in ['genres', 'themes', 'demographics']) {
      final list = j[field] as List? ?? const [];
      for (final g in list) {
        final name = (g as Map)['name']?.toString();
        if (name != null && !genres.contains(name)) genres.add(name);
      }
    }

    return AnimeMeta(
      malId: j['mal_id'] as int?,
      title: (j['title_english'] as String?)?.trim().isNotEmpty == true
          ? j['title_english'] as String
          : (j['title'] as String? ?? 'Sans titre'),
      imageUrl: (webp?['large_image_url'] ?? jpg?['large_image_url'] ?? jpg?['image_url'])
          as String?,
      synopsis: j['synopsis'] as String?,
      genres: genres,
      score: (j['score'] as num?)?.toDouble(),
      year: j['year'] as int? ??
          int.tryParse(
            ((j['aired'] as Map?)?['from'] as String? ?? '').split('-').first,
          ),
      type: j['type'] as String?,
      status: j['status'] as String?,
      episodes: j['episodes'] as int?,
    );
  }
}
