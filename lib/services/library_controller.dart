import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/anime.dart';
import '../models/anime_meta.dart';
import 'metadata_service.dart';
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
  String metaSource = 'auto'; // auto | anilist | jikan
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
        'metaSource': metaSource,
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
    s.metaSource = j['metaSource'] as String? ?? 'auto';
    s.viewMode = j['viewMode'] as String? ?? 'grid';
    s.sortMode = j['sortMode'] as String? ?? 'alpha';
    return s;
  }
}

class LibraryController extends ChangeNotifier {
  List<Anime> animes = [];
  List<String> folders = [];
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
      }), flush: true);

      if (f.existsSync()) {
        try {
          await f.copy('${f.path}.bak');
        } catch (_) {}
      }
      await tmp.rename(f.path);
      saveError = null;
    } catch (e) {
      saveError = 'La bibliothèque n'a pas pu etre enregistree.';
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

      final found =
          await Scanner.scanFolders(reachable, onProgress: (m) => _report(m));
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
    var meta = await MetadataService.smartSearch(query, source: settings.metaSource);

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
            source: settings.metaSource);
      }
    }
    if (meta == null) {
      // Une panne reseau ne doit pas condamner la fiche : on retentera
      // aux prochains demarrages, jusqu'a trois fois.
      anime.metaFailCount++;
      anime.metaFailed = anime.metaFailCount >= 3;
    } else {
      applyMeta(anime, meta);
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
    anime.imageUrl = meta.imageUrl;
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

  Future<void> clearLibrary() async {
    animes = [];
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
