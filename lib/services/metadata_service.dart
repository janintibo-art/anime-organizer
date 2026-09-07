import '../models/anime_meta.dart';
import 'anilist_api.dart';
import 'jikan_api.dart';

/// Choisit la source de metadonnees.
/// En mode automatique : AniList d'abord (rapide et complet), Jikan en
/// secours quand AniList ne trouve rien.
class MetadataService {
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
