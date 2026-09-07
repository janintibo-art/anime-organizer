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

  /// Chemins des episodes deja regardes.
  List<String> watchedPaths;

  /// Dernier episode lu et position atteinte, pour la reprise.
  String? lastEpisodePath;
  int lastPositionMs;
  int? lastPlayedAtMs;

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
    List<String>? watchedPaths,
    this.lastEpisodePath,
    this.lastPositionMs = 0,
    this.lastPlayedAtMs,
    List<Episode>? episodes,
  })  : genres = genres ?? <String>[],
        watchedPaths = watchedPaths ?? <String>[],
        episodes = episodes ?? <Episode>[];

  String get title =>
      (apiTitle != null && apiTitle!.trim().isNotEmpty) ? apiTitle! : folderTitle;

  String? get synopsis =>
      (synopsisTranslated != null && synopsisTranslated!.trim().isNotEmpty)
          ? synopsisTranslated
          : synopsisEn;

  int get watchedCount =>
      episodes.where((e) => watchedPaths.contains(e.path)).length;

  double get progress =>
      episodes.isEmpty ? 0 : watchedCount / episodes.length;

  bool get started => lastPlayedAtMs != null || watchedCount > 0;
  bool get finished => episodes.isNotEmpty && watchedCount == episodes.length;

  bool isWatched(Episode e) => watchedPaths.contains(e.path);

  /// Index du premier episode non vu, ou 0 si la serie est terminee.
  int get firstUnwatchedIndex {
    for (var i = 0; i < episodes.length; i++) {
      if (!watchedPaths.contains(episodes[i].path)) return i;
    }
    return 0;
  }

  /// Episode a relancer : celui qu'on a laisse en cours, sinon le suivant.
  int get resumeIndex {
    if (lastEpisodePath != null) {
      final i = episodes.indexWhere((e) => e.path == lastEpisodePath);
      if (i >= 0 && !watchedPaths.contains(episodes[i].path)) return i;
    }
    return firstUnwatchedIndex;
  }

  Duration get resumePosition {
    if (lastEpisodePath == null) return Duration.zero;
    final i = episodes.indexWhere((e) => e.path == lastEpisodePath);
    if (i < 0 || i != resumeIndex) return Duration.zero;
    return Duration(milliseconds: lastPositionMs);
  }

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
        'watchedPaths': watchedPaths,
        'lastEpisodePath': lastEpisodePath,
        'lastPositionMs': lastPositionMs,
        'lastPlayedAtMs': lastPlayedAtMs,
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
        watchedPaths:
            (j['watchedPaths'] as List?)?.map((e) => e.toString()).toList(),
        lastEpisodePath: j['lastEpisodePath'] as String?,
        lastPositionMs: j['lastPositionMs'] as int? ?? 0,
        lastPlayedAtMs: j['lastPlayedAtMs'] as int?,
        episodes: (j['episodes'] as List?)
                ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );
}
