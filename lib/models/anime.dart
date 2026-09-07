class Episode {
  final String path;
  final String name;

  const Episode({required this.path, required this.name});

  Map<String, dynamic> toJson() => {'path': path, 'name': name};

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        path: j['path'] as String,
        name: j['name'] as String,
      );
}

class Anime {
  /// Chemin du dossier de la serie : sert d'identifiant unique.
  final String id;

  /// Titre deduit du nom de dossier / fichier.
  String folderTitle;

  /// Titre renvoye par l'API.
  String? apiTitle;
  String? nativeTitle;

  int? malId;
  String? imageUrl;
  String? synopsisEn;
  String? synopsisTranslated;
  List<String> genres;
  double? score;
  int? popularity;
  String? studios;
  String? metaSource;
  int? year;
  String? type;
  String? status;
  int? episodesCount;

  bool metaFetched;
  bool metaFailed;
  int metaFailCount;
  bool favorite;

  List<Episode> episodes;

  Anime({
    required this.id,
    required this.folderTitle,
    this.apiTitle,
    this.nativeTitle,
    this.malId,
    this.imageUrl,
    this.synopsisEn,
    this.synopsisTranslated,
    List<String>? genres,
    this.score,
    this.popularity,
    this.studios,
    this.metaSource,
    this.year,
    this.type,
    this.status,
    this.episodesCount,
    this.metaFetched = false,
    this.metaFailed = false,
    this.metaFailCount = 0,
    this.favorite = false,
    List<Episode>? episodes,
  })  : genres = genres ?? <String>[],
        episodes = episodes ?? <Episode>[];

  String get title =>
      (apiTitle != null && apiTitle!.trim().isNotEmpty) ? apiTitle! : folderTitle;

  String? get synopsis =>
      (synopsisTranslated != null && synopsisTranslated!.trim().isNotEmpty)
          ? synopsisTranslated
          : synopsisEn;

  String get sortKey => title.toLowerCase().replaceAll(RegExp(r'^(the|le|la|les|a|an) '), '');

  Map<String, dynamic> toJson() => {
        'id': id,
        'folderTitle': folderTitle,
        'apiTitle': apiTitle,
        'nativeTitle': nativeTitle,
        'malId': malId,
        'imageUrl': imageUrl,
        'synopsisEn': synopsisEn,
        'synopsisTranslated': synopsisTranslated,
        'genres': genres,
        'score': score,
        'popularity': popularity,
        'studios': studios,
        'metaSource': metaSource,
        'year': year,
        'type': type,
        'status': status,
        'episodesCount': episodesCount,
        'metaFetched': metaFetched,
        'metaFailed': metaFailed,
        'metaFailCount': metaFailCount,
        'favorite': favorite,
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };

  factory Anime.fromJson(Map<String, dynamic> j) => Anime(
        id: j['id'] as String,
        folderTitle: j['folderTitle'] as String? ?? '',
        apiTitle: j['apiTitle'] as String?,
        nativeTitle: j['nativeTitle'] as String?,
        malId: j['malId'] as int?,
        imageUrl: j['imageUrl'] as String?,
        synopsisEn: j['synopsisEn'] as String?,
        synopsisTranslated: j['synopsisTranslated'] as String?,
        genres: (j['genres'] as List?)?.map((e) => e.toString()).toList() ?? [],
        score: (j['score'] as num?)?.toDouble(),
        popularity: j['popularity'] as int?,
        studios: j['studios'] as String?,
        metaSource: j['metaSource'] as String?,
        year: j['year'] as int?,
        type: j['type'] as String?,
        status: j['status'] as String?,
        episodesCount: j['episodesCount'] as int?,
        metaFetched: j['metaFetched'] as bool? ?? false,
        metaFailed: j['metaFailed'] as bool? ?? false,
        metaFailCount: j['metaFailCount'] as int? ?? 0,
        favorite: j['favorite'] as bool? ?? false,
        episodes: (j['episodes'] as List?)
                ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );
}
