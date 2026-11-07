import 'dart:convert';
import 'package:http/http.dart' as http;

/// Catalogue de metadonnees : ne telecharge pas de morceaux sous droits.
class AnimeThemeMatch {
  final String name;
  final String slug;
  final int? year;
  const AnimeThemeMatch(this.name, this.slug, this.year);
}

class AnimeThemeEntry {
  final String label;
  final String title;
  const AnimeThemeEntry(this.label, this.title);
}

class AnimeThemesCatalog {
  static Future<List<AnimeThemeMatch>> search(String title) async {
    final uri = Uri.https('api.animethemes.moe', '/anime/', {
      'q': title,
      'page[size]': '12',
    });
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('AnimeThemes : HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = data['anime'] as List? ?? const [];
    return raw.whereType<Map>().map((item) => AnimeThemeMatch(
      (item['name'] ?? '').toString(),
      (item['slug'] ?? '').toString(),
      item['year'] is int ? item['year'] as int : null,
    )).where((item) => item.name.isNotEmpty && item.slug.isNotEmpty).toList();
  }

  static Future<List<AnimeThemeEntry>> themes(String slug) async {
    final uri = Uri.https('api.animethemes.moe', '/anime/$slug', {
      'include': 'animethemes.song,animethemes.song.artists',
    });
    final response = await http.get(uri, headers: {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Catalogue indisponible : HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final anime = data['anime'] as Map? ?? {};
    final raw = anime['animethemes'] as List? ?? const [];
    return raw.whereType<Map>().map((theme) {
      final type = (theme['type'] ?? 'OP').toString();
      final number = (theme['sequence'] ?? '1').toString();
      final song = theme['song'] as Map? ?? {};
      final title = (song['title'] ?? 'Titre inconnu').toString();
      return AnimeThemeEntry('$type$number', title);
    }).toList();
  }
}
