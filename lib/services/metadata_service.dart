import '../models/anime_meta.dart';
import 'anilist_api.dart';
import 'jikan_api.dart';

/// Choisit la source de metadonnees.
/// En mode automatique : AniList d'abord (rapide et complet), Jikan en
/// secours quand AniList ne trouve rien.
class MetadataService {
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

  /// Essaie plusieurs formulations jusqu'a trouver une fiche.
  static Future<AnimeMeta?> smartSearch(
    String title, {
    String source = 'auto',
  }) async {
    for (final query in variants(title)) {
      final found = await search(query, source: source);
      if (found != null) return found;
    }
    return null;
  }

  static Future<AnimeMeta?> search(String title, {String source = 'auto'}) async {
    final results = await searchMany(title, source: source, limit: 1);
    return results.isEmpty ? null : results.first;
  }

  static Future<List<AnimeMeta>> searchMany(
    String title, {
    String source = 'auto',
    int limit = 8,
  }) async {
    switch (source) {
      case 'anilist':
        return AniListApi.searchMany(title, limit: limit);
      case 'jikan':
        return JikanApi.searchMany(title, limit: limit);
      default:
        final primary = await AniListApi.searchMany(title, limit: limit);
        if (primary.isNotEmpty) return primary;
        return JikanApi.searchMany(title, limit: limit);
    }
  }
}
