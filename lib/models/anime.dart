import 'vf.dart';

class Episode {
  final String path;
  final String name;

  /// Saison et numero deduits du chemin et du nom de fichier.
  final int? season;
  final int? number;

  /// OAV, generique, making-of : compte a part, pas dans la numerotation.
  final bool bonus;

  /// Fichiers .srt ou .ass poses a cote de la video.
  final List<String> subtitles;

  /// Fichiers audio separes portant le meme nom : une piste de doublage
  /// livree a part se charge alors avec la video.
  final List<String> externalAudio;

  /// Date du fichier, pour le tri « recemment ajoute ».
  final int? addedAtMs;

  const Episode({
    required this.path,
    required this.name,
    this.season,
    this.number,
    this.bonus = false,
    List<String>? subtitles,
    List<String>? externalAudio,
    this.addedAtMs,
  })  : subtitles = subtitles ?? const [],
        externalAudio = externalAudio ?? const [];

  String get label {
    if (bonus) return name;
    if (number == null) return name;
    return 'Épisode $number';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'season': season,
        'number': number,
        'bonus': bonus,
        'subtitles': subtitles,
        'externalAudio': externalAudio,
        'addedAtMs': addedAtMs,
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        path: j['path'] as String,
        name: j['name'] as String,
        season: j['season'] as int?,
        number: j['number'] as int?,
        bonus: j['bonus'] as bool? ?? false,
        subtitles:
            (j['subtitles'] as List?)?.map((e) => e.toString()).toList(),
        externalAudio:
            (j['externalAudio'] as List?)?.map((e) => e.toString()).toList(),
        addedAtMs: j['addedAtMs'] as int?,
      );
}

/// Anomalies reperees dans une serie : trous dans la numerotation,
/// fichiers en double, contenus bonus.
class SeriesIssues {
  final Map<int, List<int>> missing;
  final Map<int, List<int>> duplicates;
  final int bonusCount;

  const SeriesIssues(this.missing, this.duplicates, this.bonusCount);

  bool get isEmpty =>
      missing.isEmpty && duplicates.isEmpty && bonusCount == 0;

  int get missingCount =>
      missing.values.fold<int>(0, (sum, l) => sum + l.length);
  int get duplicateCount =>
      duplicates.values.fold<int>(0, (sum, l) => sum + l.length);
}

class Anime {
  /// Chemin du dossier de la serie : sert d'identifiant unique.
  final String id;

  /// Titre deduit du nom de dossier / fichier.
  String folderTitle;

  /// Titre renvoye par l'API.
  String? apiTitle;
  String? nativeTitle;
  String? romajiTitle;
  String? frenchTitle;

  int? malId;
  String? imageUrl;
  String? backdropUrl;
  // V26_SLIDESHOW: preferences sauvegardees par fiche.
  bool slideshowEnabled = false;
  int slideshowSeconds = 8;
  String? backdropLocalPath; // V25: image personnelle copiee dans le stockage de l’application.
  bool backdropManual = false;
  double backdropAlignX = 0.0;
  double backdropAlignY = 0.0;
  String? posterPath;
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

  /// anime | western | adult | other. Anciennes fiches = anime.
  String category;

  // V18_CREDITS: local credit markers, never change the source video.
  // Keys: s:<season> for the whole season, e:<video path> for an episode.
  // Values in milliseconds: introEnd and outroStart.
  Map<String, Map<String, int>> creditMarkers;

  Map<String, int>? creditsFor(Episode episode) =>
      creditMarkers['e:${episode.path}'] ??
      creditMarkers['s:${episode.season ?? 1}'];

  void setCreditMarker(Episode episode, bool seasonWide,
      String marker, int milliseconds) {
    final key = seasonWide ? 's:${episode.season ?? 1}' : 'e:${episode.path}';
    creditMarkers.putIfAbsent(key, () => <String, int>{})[marker] = milliseconds;
  }

  void clearCreditMarkers(Episode episode, bool seasonWide) {
    creditMarkers.remove(seasonWide ? 's:${episode.season ?? 1}' : 'e:${episode.path}');
  }

  /// Chemins des episodes deja regardes.
  List<String> watchedPaths;

  /// Pistes audio constatées pendant la lecture : chemin de l'épisode ->
  /// présence d'une piste française. Plus sûr que le nom du fichier, qui
  /// peut se tromper ou ne rien dire ; il l'emporte donc toujours.
  Map<String, bool> audioFr;

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
    this.romajiTitle,
    this.frenchTitle,
    this.malId,
    this.imageUrl,
    this.backdropUrl,
    this.backdropLocalPath,
    this.slideshowEnabled = false,
    this.slideshowSeconds = 8,
    this.backdropManual = false,
    this.backdropAlignX = 0.0,
    this.backdropAlignY = 0.0,
    this.posterPath,
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
    this.category = 'anime',
    Map<String, Map<String, int>>? creditMarkers,
    List<String>? watchedPaths,
    Map<String, bool>? audioFr,
    this.lastEpisodePath,
    this.lastPositionMs = 0,
    this.lastPlayedAtMs,
    List<Episode>? episodes,
  })  : creditMarkers = creditMarkers ?? <String, Map<String, int>>{},
        genres = genres ?? <String>[],
        watchedPaths = watchedPaths ?? <String>[],
        audioFr = audioFr ?? <String, bool>{},
        episodes = episodes ?? <Episode>[];

  /// Un épisode a une piste française : ce que la lecture a constaté, à
  /// défaut ce qu'annoncent le fichier, ses dossiers ou sa piste séparée.
  bool episodeHasVf(Episode e) {
    final constate = audioFr[e.path];
    if (constate != null) return constate;
    return Vf.inName(Vf.lastParts(e.path)) ||
        e.externalAudio.any(Vf.inAudioFile);
  }

  // Calcul mis en cache : les affiches le demandent à chaque affichage.
  // Le cache suit la liste d'épisodes : un nouveau scan la remplace, et le
  // compte est alors refait.
  int? _vfCache;
  List<Episode>? _vfPour;

  /// Nombre d'épisodes disponibles en VF, bonus exclus.
  int get vfCount {
    if (_vfCache == null || !identical(_vfPour, episodes)) {
      _vfPour = episodes;
      _vfCache = episodes.where((e) => !e.bonus && episodeHasVf(e)).length;
    }
    return _vfCache!;
  }

  bool get hasVf => vfCount > 0;

  /// Toute la série est en VF, bonus mis à part.
  bool get fullyVf {
    final hors = episodes.where((e) => !e.bonus).length;
    return hors > 0 && vfCount == hors;
  }

  /// À appeler quand une piste vient d'être constatée.
  void noteAudio(String path, bool fr) {
    audioFr[path] = fr;
    _vfCache = null;
  }

  String get title =>
      (apiTitle != null && apiTitle!.trim().isNotEmpty) ? apiTitle! : folderTitle;

  String? get synopsis =>
      (synopsisTranslated != null && synopsisTranslated!.trim().isNotEmpty)
          ? synopsisTranslated
          : synopsisEn;

  /// Date du fichier le plus recent de la serie.
  int get newestFileMs {
    var newest = 0;
    for (final e in episodes) {
      if ((e.addedAtMs ?? 0) > newest) newest = e.addedAtMs!;
    }
    return newest;
  }

  /// Titre reduit a l'essentiel, pour reperer les doublons entre dossiers.
  String get fingerprint => (apiTitle ?? folderTitle)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

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

  /// Saisons presentes, dans l'ordre. La saison 0 regroupe les fichiers
  /// dont aucune saison n'a pu etre deduite.
  List<int> get seasons {
    final set = <int>{};
    for (final e in episodes) {
      if (!e.bonus) set.add(e.season ?? 1);
    }
    final list = set.toList()..sort();
    return list;
  }

  SeriesIssues get issues {
    final bySeason = <int, List<int>>{};
    var bonus = 0;

    for (final e in episodes) {
      if (e.bonus) {
        bonus++;
        continue;
      }
      if (e.number == null) continue;
      bySeason.putIfAbsent(e.season ?? 1, () => []).add(e.number!);
    }

    final missing = <int, List<int>>{};
    final duplicates = <int, List<int>>{};

    bySeason.forEach((season, numbers) {
      final counts = <int, int>{};
      for (final n in numbers) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
      final doubled = counts.entries
          .where((e) => e.value > 1)
          .map((e) => e.key)
          .toList()
        ..sort();
      if (doubled.isNotEmpty) duplicates[season] = doubled;

      final present = counts.keys.toList()..sort();
      if (present.length < 2) return;
      final holes = <int>[];
      for (var n = present.first; n < present.last; n++) {
        if (!counts.containsKey(n)) holes.add(n);
      }
      if (holes.isNotEmpty) missing[season] = holes;
    });

    return SeriesIssues(missing, duplicates, bonus);
  }

  /// Collection a laquelle la serie appartient.
  String get collection {
    if (finished) return 'done';
    if (started) return 'watching';
    return 'todo';
  }

  String get sortKey => title.toLowerCase().replaceAll(RegExp(r'^(the|le|la|les|a|an) '), '');

  Map<String, dynamic> toJson() => {
        'id': id,
        'folderTitle': folderTitle,
        'apiTitle': apiTitle,
        'nativeTitle': nativeTitle,
        'romajiTitle': romajiTitle,
        'frenchTitle': frenchTitle,
        'malId': malId,
        'imageUrl': imageUrl,
        'backdropUrl': backdropUrl,
        'backdropLocalPath': backdropLocalPath,
        'slideshowEnabled': slideshowEnabled,
        'slideshowSeconds': slideshowSeconds,
        'backdropManual': backdropManual,
        'backdropAlignX': backdropAlignX,
        'backdropAlignY': backdropAlignY,
        'posterPath': posterPath,
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
        'category': category,
        'creditMarkers': creditMarkers,
        'watchedPaths': watchedPaths,
        'audioFr': audioFr,
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
        romajiTitle: j['romajiTitle'] as String?,
        frenchTitle: j['frenchTitle'] as String?,
        malId: j['malId'] as int?,
        imageUrl: j['imageUrl'] as String?,
        backdropUrl: j['backdropUrl'] as String?,
        backdropLocalPath: j['backdropLocalPath'] as String?,
        slideshowEnabled: j['slideshowEnabled'] as bool? ?? false,
        slideshowSeconds: (j['slideshowSeconds'] as int? ?? 8).clamp(3, 60).toInt(),
        backdropManual: j['backdropManual'] as bool? ?? false,
        backdropAlignX: (j['backdropAlignX'] as num?)?.toDouble() ?? 0.0,
        backdropAlignY: (j['backdropAlignY'] as num?)?.toDouble() ?? 0.0,
        posterPath: j['posterPath'] as String?,
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
        category: j['category'] as String? ?? 'anime',
        creditMarkers: (j['creditMarkers'] as Map?)?.map((key, value) =>
            MapEntry(key.toString(), (value as Map).map((k, v) =>
                MapEntry(k.toString(), (v as num).toInt())))),
        watchedPaths:
            (j['watchedPaths'] as List?)?.map((e) => e.toString()).toList(),
        audioFr: (j['audioFr'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v == true)),
        lastEpisodePath: j['lastEpisodePath'] as String?,
        lastPositionMs: j['lastPositionMs'] as int? ?? 0,
        lastPlayedAtMs: j['lastPlayedAtMs'] as int?,
        episodes: (j['episodes'] as List?)
                ?.map((e) => Episode.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );
}
