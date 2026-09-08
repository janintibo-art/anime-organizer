import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/anime.dart';
import '../models/anime_meta.dart';
import 'metadata_service.dart';
import 'ai_service.dart';
import 'poster_cache.dart';
import 'seed_database.dart';
import 'scanner.dart';
import 'translate_api.dart';

/// Instance unique utilisee par toute l'application.
final LibraryController library = LibraryController();

class AppSettings {
  String translationProvider = 'mymemory'; // none | mymemory | libretranslate | deepl
  String targetLang = 'fr';
  String apiKey = '';
  String libreEndpoint = 'https://libretranslate.com';
  String email = '';
  bool autoTranslate = true;
  bool autoFetch = true;
  bool scanOnStart = true;
  bool offlinePosters = true;

  // Lecteur
  bool autoNext = true;
  int skipIntroSeconds = 85;
  String preferredAudio = '';
  String preferredSubtitle = 'fr';

  // Assistant IA
  bool aiEnabled = true;
  String aiProvider = 'groq'; // groq | openrouter | custom
  String aiKey = '';
  String aiModel = 'llama-3.3-70b-versatile';
  String aiEndpoint = '';
  // auto | anilist | jikan | kitsu | animethemes | tmdb
  String metaSource = 'auto';
  String tmdbKey = '';
  String viewMode = 'grid'; // grid | list | genre
  String sortMode = 'alpha'; // alpha | score | year | episodes | recent

  Map<String, dynamic> toJson() => {
        'translationProvider': translationProvider,
        'targetLang': targetLang,
        'apiKey': apiKey,
        'libreEndpoint': libreEndpoint,
        'email': email,
        'autoTranslate': autoTranslate,
        'autoFetch': autoFetch,
        'scanOnStart': scanOnStart,
        'offlinePosters': offlinePosters,
        'autoNext': autoNext,
        'skipIntroSeconds': skipIntroSeconds,
        'preferredAudio': preferredAudio,
        'preferredSubtitle': preferredSubtitle,
        'aiEnabled': aiEnabled,
        'aiProvider': aiProvider,
        'aiKey': aiKey,
        'aiModel': aiModel,
        'aiEndpoint': aiEndpoint,
        'metaSource': metaSource,
        'tmdbKey': tmdbKey,
        'viewMode': viewMode,
        'sortMode': sortMode,
      };

  static AppSettings fromJson(Map<String, dynamic> j) {
    final s = AppSettings();
    s.translationProvider = j['translationProvider'] as String? ?? 'mymemory';
    s.targetLang = j['targetLang'] as String? ?? 'fr';
    s.apiKey = j['apiKey'] as String? ?? '';
    s.libreEndpoint = j['libreEndpoint'] as String? ?? 'https://libretranslate.com';
    s.email = j['email'] as String? ?? '';
    s.autoTranslate = j['autoTranslate'] as bool? ?? true;
    s.autoFetch = j['autoFetch'] as bool? ?? true;
    s.scanOnStart = j['scanOnStart'] as bool? ?? true;
    s.offlinePosters = j['offlinePosters'] as bool? ?? true;
    s.autoNext = j['autoNext'] as bool? ?? true;
    s.skipIntroSeconds = j['skipIntroSeconds'] as int? ?? 85;
    s.preferredAudio = j['preferredAudio'] as String? ?? '';
    s.preferredSubtitle = j['preferredSubtitle'] as String? ?? 'fr';
    s.aiEnabled = j['aiEnabled'] as bool? ?? true;
    s.aiProvider = j['aiProvider'] as String? ?? 'groq';
    s.aiKey = j['aiKey'] as String? ?? '';
    s.aiModel = j['aiModel'] as String? ?? 'llama-3.3-70b-versatile';
    s.aiEndpoint = j['aiEndpoint'] as String? ?? '';
    s.metaSource = j['metaSource'] as String? ?? 'auto';
    s.tmdbKey = j['tmdbKey'] as String? ?? '';
    s.viewMode = j['viewMode'] as String? ?? 'grid';
    s.sortMode = j['sortMode'] as String? ?? 'alpha';
    return s;
  }
}

class LibraryController extends ChangeNotifier {
  List<Anime> animes = [];
  List<String> folders = [];

  /// Series reperees dans l'onglet Decouvrir et mises de cote.
  List<AnimeMeta> wishlist = [];

  /// Ta propre base : chaque correction manuelle ou par l'IA est retenue.
  /// Un dossier deja identifie ne sera plus jamais recherche.
  Map<String, String> knownTitles = {};

  String _key(String folderTitle) =>
      MetadataService.stripAccents(folderTitle).replaceAll(
          RegExp(r'[^a-z0-9]'), '');

  void remember(String folderTitle, String resolvedQuery) {
    final key = _key(folderTitle);
    if (key.length < 3 || resolvedQuery.trim().isEmpty) return;
    knownTitles[key] = resolvedQuery.trim();
  }

  String? recall(String folderTitle) => knownTitles[_key(folderTitle)];
  AppSettings settings = AppSettings();

  bool busy = false;
  String status = '';
  double progress = 0;

  /// Nombre de series decouvertes lors du dernier scan.
  int lastNewCount = 0;

  /// Dossiers injoignables au dernier scan (disque debranche, permission
  /// refusee). Leurs fiches sont conservees plutot que supprimees.
  List<String> unreachableFolders = [];

  File? _file;

  Future<File> _storeFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _file = File(p.join(dir.path, 'library.json'));
    return _file!;
  }

  /// Message affiche si la derniere sauvegarde a echoue.
  String? saveError;

  Future<void> load() async {
    final f = await _storeFile();
    final backup = File('${f.path}.bak');
    for (final candidate in [f, backup]) {
      if (!candidate.existsSync()) continue;
      if (await _loadFrom(candidate)) {
        notifyListeners();
        return;
      }
    }
    notifyListeners();
  }

  Future<bool> _loadFrom(File file) async {
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      folders = (data['folders'] as List?)?.map((e) => e.toString()).toList() ?? [];
      settings = AppSettings.fromJson(
          Map<String, dynamic>.from(data['settings'] as Map? ?? {}));
      animes = (data['animes'] as List?)
              ?.map((e) => Anime.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      knownTitles = ((data['knownTitles'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));
      wishlist = (data['wishlist'] as List?)
              ?.map((e) =>
                  AnimeMeta.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [];
      return true;
    } catch (_) {
      // Fichier illisible : on tentera la copie de secours.
      return false;
    }
  }

  /// Ecriture atomique : on ecrit un fichier temporaire, on archive la version
  /// precedente, puis on renomme. Une coupure ne peut pas laisser un JSON
  /// tronque a la place de la bibliotheque.
  Future<void> save() async {
    try {
      final f = await _storeFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'folders': folders,
        'settings': settings.toJson(),
        'animes': animes.map((a) => a.toJson()).toList(),
        'wishlist': wishlist.map((w) => w.toJson()).toList(),
        'knownTitles': knownTitles,
      }), flush: true);

      if (f.existsSync()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (_) {}
      }
      await tmp.rename(f.path);
      saveError = null;
    } catch (e) {
      saveError = 'La bibliothèque n\'a pas pu être enregistrée.';
      notifyListeners();
    }
  }

  /// Rafraichit les ecrans qui ecoutent le controleur.
  void refresh() => notifyListeners();

  void _report(String message, [double value = 0]) {
    status = message;
    progress = value;
    notifyListeners();
  }

  Future<void> addFolder(String path) async {
    if (folders.contains(path)) return;
    folders.add(path);
    await save();
    notifyListeners();
  }

  Future<void> removeFolder(String path, {bool dropEntries = true}) async {
    folders.remove(path);
    if (dropEntries) {
      animes.removeWhere((a) => p.isWithin(path, a.id) || p.equals(path, a.id));
    }
    await save();
    notifyListeners();
  }

  /// Scanne les dossiers, fusionne avec l'existant, puis complete les fiches.
  Future<void> scan({bool fetchMetadata = true}) async {
    if (busy || folders.isEmpty) return;
    busy = true;
    _report('Analyse des dossiers');

    try {
      // Un dossier injoignable ne doit pas effacer les fiches deja connues.
      final reachable = <String>[];
      final unreachable = <String>[];
      for (final f in folders) {
        (Directory(f).existsSync() ? reachable : unreachable).add(f);
      }
      unreachableFolders = unreachable;

      // Le parcours des dossiers part dans un isolate : sur une carte SD
      // bien remplie, l'interface reste fluide.
      _report('Analyse des dossiers');
      final raw = await compute(Scanner.scanFoldersJson, reachable);
      final found = raw
          .map((m) => Anime.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final existing = {for (final a in animes) a.id: a};
      final merged = <Anime>[];
      var discovered = 0;

      for (final item in found) {
        final old = existing[item.id];
        if (old != null) {
          old.episodes = item.episodes;
          old.folderTitle = item.folderTitle;
          merged.add(old);
        } else {
          merged.add(item);
          discovered++;
        }
      }

      // Series appartenant a un dossier momentanement inaccessible.
      for (final a in animes) {
        if (merged.any((m) => m.id == a.id)) continue;
        final orphan = unreachable.any(
            (f) => p.equals(f, a.id) || p.isWithin(f, a.id));
        if (orphan) merged.add(a);
      }

      lastNewCount = discovered;
      animes = merged;
      await save();
      notifyListeners();

      if (fetchMetadata && settings.autoFetch) {
        final todo = animes
            .where((a) => !a.metaFetched && a.metaFailCount < 3)
            .toList();
        for (var i = 0; i < todo.length; i++) {
          _report('Fiche ${i + 1}/${todo.length} : ${todo[i].folderTitle}',
              (i + 1) / todo.length);
          await fetchOne(todo[i], persist: false);
        }
        await save();
      }
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Scan lance a l'ouverture de l'application : detecte les nouveaux
  /// dossiers sans retoucher aux fiches deja enregistrees.
  Future<void> startupScan() async {
    if (!settings.scanOnStart || folders.isEmpty || busy) return;
    await scan();
  }

  /// Recupere image, synopsis et genres pour une serie.
  Future<void> fetchOne(Anime anime, {String? overrideQuery, bool persist = true}) async {
    final query = overrideQuery ?? anime.folderTitle;
    final count = anime.episodes.where((e) => !e.bonus).length;

    // 1. Ta memoire : ce dossier a deja ete identifie une fois.
    var resolved = overrideQuery ?? recall(anime.folderTitle);

    // 2. La base locale : elle traduit un titre francais en romaji,
    //    ce que les bases en ligne savent chercher.
    SeedEntry? seed;
    if (resolved == null) {
      seed = SeedDatabase.match(anime.folderTitle, episodeCount: count);
      if (seed != null) resolved = seed.searchQuery;
    }

    var meta = await MetadataService.smartSearch(
      resolved ?? query,
      source: settings.metaSource,
      episodeCount: count,
      tmdbKey: settings.tmdbKey,
    );

    // 3. Rien en ligne mais la base locale connait la serie : on l'applique
    //    telle quelle, quitte a completer l'affiche plus tard.
    if (meta == null && seed != null) {
      applyMeta(anime, seed.toMeta());
      anime.frenchTitle = seed.french;
      remember(anime.folderTitle, seed.searchQuery);
      if (persist) await save();
      notifyListeners();
      return;
    }

    // Titre francais : on le traduit en anglais et on retente.
    if (meta == null &&
        settings.translationProvider != 'none' &&
        MetadataService.looksFrench(query)) {
      final english = await TranslateApi.translate(
        query,
        provider: settings.translationProvider,
        targetLang: 'en',
        sourceLang: 'fr',
        apiKey: settings.apiKey,
        endpoint: settings.libreEndpoint,
        email: settings.email,
      );
      if (english != null && english.trim().isNotEmpty) {
        meta = await MetadataService.smartSearch(english,
            source: settings.metaSource,
            episodeCount: anime.episodes.where((e) => !e.bonus).length);
      }
    }

    // Dernier recours : l'IA identifie la serie et donne son vrai titre.
    AiTitles? ai;
    if (meta == null && settings.aiEnabled && settings.aiKey.isNotEmpty) {
      ai = await AiService.identify(
        folderTitle: query,
        provider: settings.aiProvider,
        apiKey: settings.aiKey,
        model: settings.aiModel,
        custom: settings.aiEndpoint,
      );
      if (ai != null && ai.usable) {
        meta = await MetadataService.smartSearch(
          ai.searchQuery,
          source: settings.metaSource,
          episodeCount: count,
          tmdbKey: settings.tmdbKey,
        );
        if (meta == null && ai.english.isNotEmpty) {
          meta = await MetadataService.smartSearch(
            ai.english,
            source: settings.metaSource,
            episodeCount: count,
            tmdbKey: settings.tmdbKey,
          );
        }
      }
    }
    if (meta == null) {
      // Une panne reseau ne doit pas condamner la fiche : on retentera
      // aux prochains demarrages, jusqu'a trois fois.
      anime.metaFailCount++;
      anime.metaFailed = anime.metaFailCount >= 3;
    } else {
      applyMeta(anime, meta);
      remember(anime.folderTitle, meta.titleRomaji ?? meta.title);
      if (seed != null && seed.french.isNotEmpty) {
        anime.frenchTitle = seed.french;
      }
      if (ai != null && ai.usable) {
        if (ai.french.isNotEmpty) anime.frenchTitle = ai.french;
        if (ai.japanese.isNotEmpty) anime.nativeTitle ??= ai.japanese;
        if (ai.romaji.isNotEmpty) anime.romajiTitle ??= ai.romaji;
      }
      if (settings.offlinePosters) {
        anime.posterPath = await PosterCache.ensure(anime.id, anime.imageUrl);
      }
      if (settings.autoTranslate && settings.translationProvider != 'none') {
        await translateOne(anime, persist: false);
      }
    }
    if (persist) await save();
    notifyListeners();
  }

  void applyMeta(Anime anime, AnimeMeta meta) {
    anime.malId = meta.sourceId;
    anime.metaSource = meta.source;
    anime.apiTitle = meta.title;
    anime.nativeTitle = meta.titleNative;
    anime.romajiTitle = meta.titleRomaji;
    anime.imageUrl = meta.imageUrl;
    anime.posterPath = null;
    anime.synopsisEn = meta.synopsis;
    anime.synopsisTranslated = null;
    anime.genres = meta.genres;
    anime.score = meta.score;
    anime.popularity = meta.popularity;
    anime.studios = meta.studios;
    anime.year = meta.year;
    anime.type = meta.type;
    anime.status = meta.status;
    anime.episodesCount = meta.episodes;
    anime.metaFetched = true;
    anime.metaFailed = false;
  }

  Future<bool> translateOne(Anime anime, {bool persist = true}) async {
    if (anime.synopsisEn == null || anime.synopsisEn!.trim().isEmpty) return false;
    final result = await TranslateApi.translate(
      anime.synopsisEn!,
      provider: settings.translationProvider,
      targetLang: settings.targetLang,
      apiKey: settings.apiKey,
      endpoint: settings.libreEndpoint,
      email: settings.email,
    );
    if (result != null && result.trim().isNotEmpty) {
      anime.synopsisTranslated = result;
      if (persist) await save();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Traduit toutes les fiches qui ne le sont pas encore.
  Future<void> translateAll() async {
    if (busy) return;
    busy = true;
    final todo = animes
        .where((a) =>
            a.synopsisEn != null &&
            a.synopsisEn!.isNotEmpty &&
            (a.synopsisTranslated == null || a.synopsisTranslated!.isEmpty))
        .toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        _report('Traduction ${i + 1}/${todo.length}', (i + 1) / todo.length);
        await translateOne(todo[i], persist: false);
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Relance la recherche pour toutes les fiches sans metadonnees.
  Future<void> retryFailed() async {
    if (busy) return;
    busy = true;
    final todo = animes.where((a) => !a.metaFetched).toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        todo[i].metaFailed = false;
        todo[i].metaFailCount = 0;
        _report('Fiche ${i + 1}/${todo.length}', (i + 1) / todo.length);
        await fetchOne(todo[i], persist: false);
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
  }

  /// Marque un episode comme vu ou non vu.
  Future<void> setWatched(Anime anime, Episode episode, bool watched) async {
    if (watched) {
      if (!anime.watchedPaths.contains(episode.path)) {
        anime.watchedPaths.add(episode.path);
      }
    } else {
      anime.watchedPaths.remove(episode.path);
    }
    await save();
    notifyListeners();
  }

  Future<void> markAllWatched(Anime anime, bool watched) async {
    anime.watchedPaths = watched ? anime.episodes.map((e) => e.path).toList() : [];
    await save();
    notifyListeners();
  }

  /// Enregistre la position de lecture. Au-dela de 92 % l'episode est
  /// considere comme vu : le generique de fin ne merite pas d'etre subi.
  Future<void> savePlayback(
    Anime anime,
    Episode episode,
    Duration position,
    Duration duration,
  ) async {
    anime.lastEpisodePath = episode.path;
    anime.lastPositionMs = position.inMilliseconds;
    anime.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;

    if (duration.inSeconds > 0 &&
        position.inMilliseconds / duration.inMilliseconds > 0.92 &&
        !anime.watchedPaths.contains(episode.path)) {
      anime.watchedPaths.add(episode.path);
      anime.lastPositionMs = 0;
    }
    await save();
    notifyListeners();
  }

  /// Series commencees mais pas terminees, la plus recente en tete.
  List<Anime> get continueWatching {
    final list = animes
        .where((a) => a.started && !a.finished && a.episodes.isNotEmpty)
        .toList()
      ..sort((a, b) =>
          (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0));
    return list.take(12).toList();
  }

  List<Anime> get favorites =>
      animes.where((a) => a.favorite).toList()
        ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

  int get totalEpisodes =>
      animes.fold<int>(0, (sum, a) => sum + a.episodes.length);

  Future<void> toggleFavorite(Anime anime) async {
    anime.favorite = !anime.favorite;
    await save();
    notifyListeners();
  }

  Map<String, dynamic> _snapshot() => {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'folders': folders,
        'settings': settings.toJson(),
        'animes': animes.map((a) => a.toJson()).toList(),
        'wishlist': wishlist.map((w) => w.toJson()).toList(),
        'knownTitles': knownTitles,
      };

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Écrit une sauvegarde lisible dans le dossier choisi.
  Future<String> exportLibrary(String folder) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-${_two(now.hour)}${_two(now.minute)}';
    final file =
        File(p.join(folder, 'anime-organizer-sauvegarde-$stamp.json'));
    await file.writeAsString(jsonEncode(_snapshot()), flush: true);
    return file.path;
  }

  /// Restaure une sauvegarde. En mode fusion, les fiches et la progression
  /// sont reprises mais la liste des fichiers reste celle du disque.
  Future<int> importLibrary(String path, {bool merge = true}) async {
    final data =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final incoming = (data['animes'] as List? ?? [])
        .map((e) => Anime.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    if (!merge) {
      animes = incoming;
      folders = (data['folders'] as List?)?.map((e) => e.toString()).toList() ??
          folders;
    } else {
      final byId = {for (final a in animes) a.id: a};
      for (final b in incoming) {
        final current = byId[b.id];
        if (current == null) {
          animes.add(b);
          continue;
        }
        current.apiTitle = b.apiTitle ?? current.apiTitle;
        current.nativeTitle = b.nativeTitle ?? current.nativeTitle;
        current.malId = b.malId ?? current.malId;
        current.imageUrl = b.imageUrl ?? current.imageUrl;
        current.posterPath = b.posterPath ?? current.posterPath;
        current.synopsisEn = b.synopsisEn ?? current.synopsisEn;
        current.synopsisTranslated =
            b.synopsisTranslated ?? current.synopsisTranslated;
        if (b.genres.isNotEmpty) current.genres = b.genres;
        current.score = b.score ?? current.score;
        current.popularity = b.popularity ?? current.popularity;
        current.studios = b.studios ?? current.studios;
        current.year = b.year ?? current.year;
        current.type = b.type ?? current.type;
        current.status = b.status ?? current.status;
        current.episodesCount = b.episodesCount ?? current.episodesCount;
        current.metaFetched = current.metaFetched || b.metaFetched;
        current.favorite = current.favorite || b.favorite;
        for (final w in b.watchedPaths) {
          if (!current.watchedPaths.contains(w)) current.watchedPaths.add(w);
        }
        if ((b.lastPlayedAtMs ?? 0) > (current.lastPlayedAtMs ?? 0)) {
          current.lastPlayedAtMs = b.lastPlayedAtMs;
          current.lastEpisodePath = b.lastEpisodePath;
          current.lastPositionMs = b.lastPositionMs;
        }
      }
    }

    await save();
    notifyListeners();
    return incoming.length;
  }

  /// Demande à l'IA d'identifier une série, puis relance la recherche
  /// de fiche avec le titre qu'elle donne. Renvoie un message à afficher.
  Future<String> identifyWithAi(Anime anime) async {
    if (!settings.aiEnabled || settings.aiKey.isEmpty) {
      return 'Renseigne une clé IA dans les réglages.';
    }
    final ai = await AiService.identify(
      folderTitle: anime.folderTitle,
      provider: settings.aiProvider,
      apiKey: settings.aiKey,
      model: settings.aiModel,
      custom: settings.aiEndpoint,
    );
    if (ai == null) {
      return AiService.lastError ?? 'L\'IA n\'a pas répondu.';
    }
    if (!ai.usable) return 'L\'IA n\'a pas reconnu cette série.';

    if (ai.french.isNotEmpty) anime.frenchTitle = ai.french;
    if (ai.japanese.isNotEmpty) anime.nativeTitle = ai.japanese;
    if (ai.romaji.isNotEmpty) anime.romajiTitle = ai.romaji;

    final meta = await MetadataService.smartSearch(ai.searchQuery,
        source: settings.metaSource, tmdbKey: settings.tmdbKey);
    if (meta != null) {
      final french = anime.frenchTitle;
      final japanese = anime.nativeTitle;
      applyMeta(anime, meta);
      anime.frenchTitle = french;
      anime.nativeTitle ??= japanese;
      if (settings.offlinePosters) {
        anime.posterPath = await PosterCache.ensure(anime.id, anime.imageUrl);
      }
      if (settings.autoTranslate && settings.translationProvider != 'none') {
        await translateOne(anime, persist: false);
      }
      remember(anime.folderTitle, ai.searchQuery);
      await save();
      notifyListeners();
      return 'Identifiée : ${meta.title}';
    }

    await save();
    notifyListeners();
    return 'Titres mis à jour, mais aucune fiche trouvée pour ${ai.searchQuery}.';
  }

  /// Télécharge les affiches manquantes pour un usage hors connexion.
  Future<int> cachePosters() async {
    if (busy) return 0;
    busy = true;
    var done = 0;
    final todo = animes
        .where((a) =>
            a.imageUrl != null &&
            a.imageUrl!.isNotEmpty &&
            !PosterCache.exists(a.posterPath))
        .toList();
    try {
      for (var i = 0; i < todo.length; i++) {
        _report('Affiche ${i + 1}/${todo.length}', (i + 1) / todo.length);
        final path = await PosterCache.ensure(todo[i].id, todo[i].imageUrl);
        if (path != null) {
          todo[i].posterPath = path;
          done++;
        }
      }
      await save();
    } finally {
      busy = false;
      _report('');
    }
    return done;
  }

  // ------------------------------------------------------------- Decouvrir

  bool inWishlist(AnimeMeta meta) =>
      wishlist.any((w) => w.source == meta.source && w.sourceId == meta.sourceId);

  Future<void> toggleWishlist(AnimeMeta meta) async {
    if (inWishlist(meta)) {
      wishlist.removeWhere(
          (w) => w.source == meta.source && w.sourceId == meta.sourceId);
    } else {
      wishlist.insert(0, meta);
    }
    await save();
    notifyListeners();
  }

  /// Serie du disque correspondant a une fiche du catalogue, s'il y en a une.
  Anime? localMatch(AnimeMeta meta) {
    final keys = <String>{
      meta.fingerprint,
      if (meta.titleRomaji != null)
        meta.titleRomaji!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
    }..removeWhere((k) => k.length < 4);

    for (final a in animes) {
      if (a.malId != null && a.malId == meta.sourceId && a.metaSource == meta.source) {
        return a;
      }
      if (keys.contains(a.fingerprint)) return a;
    }
    return null;
  }

  /// Autres dossiers contenant apparemment la même série.
  List<Anime> duplicatesOf(Anime anime) {
    final key = anime.fingerprint;
    if (key.length < 4) return const [];
    return animes
        .where((a) => a.id != anime.id && a.fingerprint == key)
        .toList();
  }

  /// Séries dont la fiche n'a pas pu être identifiée.
  List<Anime> get unmatched =>
      animes.where((a) => !a.metaFetched).toList()
        ..sort((a, b) => a.folderTitle.compareTo(b.folderTitle));

  Future<void> clearLibrary() async {
    animes = [];
    await PosterCache.clear();
    await save();
    notifyListeners();
  }

  List<String> get allGenres {
    final set = <String>{};
    for (final a in animes) {
      set.addAll(a.genres);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// Liste filtree et triee pour l'ecran d'accueil.
  List<Anime> view({String query = '', String genre = '', bool favoritesOnly = false}) {
    final q = query.trim().toLowerCase();
    var list = animes.where((a) {
      if (favoritesOnly && !a.favorite) return false;
      if (genre.isNotEmpty && !a.genres.contains(genre)) return false;
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          a.folderTitle.toLowerCase().contains(q) ||
          a.genres.any((g) => g.toLowerCase().contains(q));
    }).toList();

    switch (settings.sortMode) {
      case 'score':
        list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
        break;
      case 'recent':
        list.sort((a, b) => b.newestFileMs.compareTo(a.newestFileMs));
        break;
      case 'popularity':
        list.sort((a, b) => (b.popularity ?? -1).compareTo(a.popularity ?? -1));
        break;
      case 'year':
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case 'episodes':
        list.sort((a, b) => b.episodes.length.compareTo(a.episodes.length));
        break;
      case 'genre':
        list.sort((a, b) {
          final ga = a.genres.isEmpty ? 'zzz' : a.genres.first.toLowerCase();
          final gb = b.genres.isEmpty ? 'zzz' : b.genres.first.toLowerCase();
          final c = ga.compareTo(gb);
          return c != 0 ? c : a.sortKey.compareTo(b.sortKey);
        });
        break;
      default:
        list.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    }
    return list;
  }

  /// Regroupement par genre pour l'affichage en rayons.
  Map<String, List<Anime>> groupedByGenre({String query = ''}) {
    final map = <String, List<Anime>>{};
    for (final a in view(query: query)) {
      if (a.genres.isEmpty) {
        map.putIfAbsent('Sans genre', () => []).add(a);
      }
      for (final g in a.genres) {
        map.putIfAbsent(g, () => []).add(a);
      }
    }
    return map;
  }

  Future<void> updateSettings(void Function(AppSettings s) change) async {
    change(settings);
    await save();
    notifyListeners();
  }

  bool episodeExists(Episode e) => File(e.path).existsSync();
}
