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

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'source': source,
        'title': title,
        'titleNative': titleNative,
        'titleRomaji': titleRomaji,
        'imageUrl': imageUrl,
        'synopsis': synopsis,
        'genres': genres,
        'score': score,
        'popularity': popularity,
        'year': year,
        'type': type,
        'status': status,
        'episodes': episodes,
        'studios': studios,
      };

  factory AnimeMeta.fromJson(Map<String, dynamic> j) => AnimeMeta(
        sourceId: j['sourceId'] as int?,
        source: j['source'] as String? ?? 'anilist',
        title: j['title'] as String? ?? 'Sans titre',
        titleNative: j['titleNative'] as String?,
        titleRomaji: j['titleRomaji'] as String?,
        imageUrl: j['imageUrl'] as String?,
        synopsis: j['synopsis'] as String?,
        genres:
            (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        score: (j['score'] as num?)?.toDouble(),
        popularity: j['popularity'] as int?,
        year: j['year'] as int?,
        type: j['type'] as String?,
        status: j['status'] as String?,
        episodes: j['episodes'] as int?,
        studios: j['studios'] as String?,
      );

  /// Empreinte du titre, pour reperer une serie deja presente sur le disque.
  String get fingerprint =>
      title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Sous-titre affiche dans les listes de resultats.
  String get summaryLine => [
        if (year != null) '$year',
        if (type != null) type!,
        if (episodes != null) '$episodes ep.',
        source == 'anilist' ? 'AniList' : 'MyAnimeList',
      ].join(' · ');
}
