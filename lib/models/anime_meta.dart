/// Metadonnees d'une serie, quelle que soit la source (AniList ou Jikan).
class AnimeMeta {
  final int? sourceId;
  final String source; // 'anilist' ou 'jikan'
  final String title;
  final String? titleNative;
  final String? titleRomaji;
  final String? imageUrl;
  final String? synopsis;
  final List<String> genres;
  final double? score;
  final int? popularity;
  final int? year;
  final String? type;
  final String? status;
  final int? episodes;
  final String? studios;

  const AnimeMeta({
    this.sourceId,
    required this.source,
    required this.title,
    this.titleNative,
    this.titleRomaji,
    this.imageUrl,
    this.synopsis,
    this.genres = const [],
    this.score,
    this.popularity,
    this.year,
    this.type,
    this.status,
    this.episodes,
    this.studios,
  });

  /// Sous-titre affiche dans les listes de resultats.
  String get summaryLine => [
        if (year != null) '$year',
        if (type != null) type!,
        if (episodes != null) '$episodes ep.',
        source == 'anilist' ? 'AniList' : 'MyAnimeList',
      ].join(' · ');
}
