import 'dart:convert';
import 'package:http/http.dart' as http;

/// Recherche uniquement une image panoramique de la serie correspondante.
/// Une image sans rapport ne doit jamais remplacer l'affiche existante.
class BackdropService {
  static String _norm(String s) => s.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _similarity(String a, String b) {
    final x = _norm(a), y = _norm(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1;
    if (x.length >= 6 && y.length >= 6 && (x.contains(y) || y.contains(x))) {
      return 0.9;
    }
    final aa = x.split(' ').where((w) => w.length > 2).toSet();
    final bb = y.split(' ').where((w) => w.length > 2).toSet();
    if (aa.isEmpty || bb.isEmpty) return 0;
    return aa.intersection(bb).length / aa.union(bb).length;
  }

  /// Panoramas de la fiche la plus proche du titre; les autres series sont exclues.
  static Future<List<String>> findBackdrops(String title, String apiKey) async {
    if (title.trim().isEmpty || apiKey.trim().isEmpty) return const [];
    try {
      for (final type in ['tv', 'movie']) {
        final search = Uri.https('api.themoviedb.org', '/3/search/$type', {
          'api_key': apiKey.trim(), 'query': title,
          'language': 'en-US', 'include_adult': 'false',
        });
        final response = await http.get(search).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        Map<String, dynamic>? match;
        var topScore = 0.0;
        for (final item in (data['results'] as List? ?? const [])) {
          if (item is! Map) continue;
          final candidate = Map<String, dynamic>.from(item);
          final name = (candidate['name'] ?? candidate['title'] ?? '').toString();
          final original = (candidate['original_name'] ?? candidate['original_title'] ?? '').toString();
          final score = _similarity(title, name) > _similarity(title, original)
              ? _similarity(title, name) : _similarity(title, original);
          if (score > topScore) { match = candidate; topScore = score; }
        }
        if (match == null || topScore < 0.78 || match['id'] == null) continue;
        final id = match['id'];
        final imagesUri = Uri.https('api.themoviedb.org', '/3/$type/$id/images', {
          'api_key': apiKey.trim(), 'include_image_language': 'en,null',
        });
        final res = await http.get(imagesUri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final imageData = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final backdrops = (imageData['backdrops'] as List? ?? const [])
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where((v) => (v['width'] as num? ?? 0) >= 800 &&
                           (v['aspect_ratio'] as num? ?? 0) >= 1.5 &&
                           v['file_path'] is String)
            .toList()
          ..sort((a, b) => ((b['vote_average'] as num?) ?? 0)
              .compareTo((a['vote_average'] as num?) ?? 0));
        final paths = <String>{};
        for (final v in backdrops.take(30)) {
          final path = v['file_path'] as String;
          if (path.startsWith('/')) paths.add('https://image.tmdb.org/t/p/w1280$path');
        }
        if (paths.isNotEmpty) return paths.take(18).toList();
      }
    } catch (_) {
      // Reseau ou TMDB indisponible : le fond actuel reste en place.
    }
    return const [];
  }

  static Future<String?> findBackdrop(String title, String apiKey) async {
    if (apiKey.trim().isEmpty || title.trim().isEmpty) return null;
    try {
      for (final type in ['tv', 'movie']) {
        final uri = Uri.https('api.themoviedb.org', '/3/search/$type', {
          'api_key': apiKey.trim(),
          'query': title,
          'language': 'en-US',
          'include_adult': 'false',
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final options = data['results'] as List? ?? const [];
        Map<String, dynamic>? best;
        var bestScore = 0.0;
        for (final item in options) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final name = (m['name'] ?? m['title'] ?? '').toString();
          final original = (m['original_name'] ?? m['original_title'] ?? '').toString();
          final score = _similarity(title, name) > _similarity(title, original)
              ? _similarity(title, name) : _similarity(title, original);
          if (score > bestScore && m['backdrop_path'] != null) {
            bestScore = score;
            best = m;
          }
        }
        if (bestScore >= 0.78 && best != null) {
          final path = best['backdrop_path'].toString();
          if (path.startsWith('/')) return 'https://image.tmdb.org/t/p/w1280$path';
        }
      }
    } catch (_) {
      // Une API en panne ne bloque jamais l'affichage des fiches.
    }
    return null;
  }
}
