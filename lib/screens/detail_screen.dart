import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
// V28_GALLERY_VISUELLE: aperçus, ordre, suppression et ouverture du dossier.

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../main.dart';
import '../models/anime.dart';
import '../models/anime_meta.dart';
import '../services/library_controller.dart';
import '../services/backdrop_service.dart';
import '../services/capture_gallery.dart';
import '../services/theme_audio_service.dart';
import '../services/metadata_service.dart';
import '../services/scanner.dart';
import '../widgets/poster_image.dart';
import 'genre_links.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final Anime anime;
  const DetailScreen({super.key, required this.anime});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _working = false;
  bool _showOriginal = false;
  bool _immersiveBackground = true;

  // V26_GALLERY: les images sont conservees hors des fichiers video.
  List<String> _gallery = [];
  int _galleryIndex = 0;
  Timer? _slideshowTimer;
  // V32: lecteur indépendant de la vidéo, libéré quand on quitte la fiche.
  final Player _themePlayer = Player();
  bool _themePlaying = false;
  bool _themeBusy = false;
  Timer? _themeFade;
  String? _themeError;

  Future<void> _stopTheme() async {
    _themeFade?.cancel();
    try { await _themePlayer.pause(); } catch (_) {}
    if (mounted) setState(() => _themePlaying = false);
  }

  Future<void> _playTheme({bool force = false}) async {
    final path = anime.themeAudioPath;
    if (path == null || path.isEmpty || (!force && !anime.themeAutoplay)) return;
    if (!await File(path).exists()) {
      if (mounted) setState(() => _themeError = 'Musique introuvable.');
      return;
    }
    _themeFade?.cancel();
    try {
      await _themePlayer.setPlaylistMode(
          anime.themeLoop ? PlaylistMode.single : PlaylistMode.none);
      await _themePlayer.setVolume(0);
      await _themePlayer.open(Media(Uri.file(path).toString()));
      if (!mounted) return;
      setState(() { _themePlaying = true; _themeError = null; });
      var step = 0;
      _themeFade = Timer.periodic(const Duration(milliseconds: 110), (timer) {
        if (!mounted || !_themePlaying || step >= 10) {
          timer.cancel();
          return;
        }
        step++;
        unawaited(_themePlayer.setVolume(anime.themeVolume * step / 10));
        if (step >= 10) timer.cancel();
      });
    } catch (e) {
      if (mounted) setState(() => _themeError = 'Lecture audio impossible : $e');
    }
  }

  Future<void> _toggleTheme() async {
    if (_themePlaying) { await _stopTheme(); }
    else { await _playTheme(force: true); }
  }

  static Duration? _parseMusicTime(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[1]);
    if (minutes == null || seconds == null || minutes < 0 ||
        seconds < 0 || seconds >= 60) return null;
    return Duration(minutes: minutes, seconds: seconds);
  }

  Future<void> _importThemeAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: ['mp3', 'flac', 'ogg', 'wav', 'm4a', 'aac', 'opus']);
    if (result == null || result.files.single.path == null) return;
    if (mounted) setState(() => _themeBusy = true);
    try {
      await _stopTheme();
      final path = await ThemeAudioService.importAudio(
        anime, result.files.single.path!);
      anime.themeAudioPath = path;
      await library.save();
      if (mounted) await _playTheme(force: true);
    } catch (e) {
      if (mounted) setState(() => _themeError = e.toString());
    } finally {
      if (mounted) setState(() => _themeBusy = false);
    }
  }

  Future<void> _extractThemeAudio() async {
    if (!Platform.isWindows || anime.episodes.isEmpty) return;
    int selected = 0;
    final from = TextEditingController(text: '00:00');
    final to = TextEditingController(text: '01:30');
    final selection = await showDialog<(int, Duration, Duration)>(
      context: context, builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: const Text('Extraire un générique'),
          content: SizedBox(width: 460, child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              const Text('Choisis un épisode, puis les positions début et fin (mm:ss).'),
              const SizedBox(height: 12),
              DropdownButton<int>(isExpanded: true, value: selected,
                items: [for (var i = 0; i < anime.episodes.length; i++)
                  DropdownMenuItem(value: i,
                    child: Text(anime.episodes[i].label,
                      overflow: TextOverflow.ellipsis))],
                onChanged: (v) { if (v != null) change(() => selected = v); }),
              TextField(controller: from, decoration:
                const InputDecoration(labelText: 'Début (mm:ss)')),
              TextField(controller: to, decoration:
                const InputDecoration(labelText: 'Fin (mm:ss)')),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
            FilledButton(onPressed: () {
              final start = _parseMusicTime(from.text);
              final end = _parseMusicTime(to.text);
              if (start == null || end == null || end <= start ||
                  end - start > const Duration(minutes: 5)) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Indique une durée de 1 seconde à 5 minutes.')));
                return;
              }
              Navigator.pop(ctx, (selected, start, end));
            }, child: const Text('Extraire')),
          ])));
    from.dispose();
    to.dispose();
    if (selection == null || !mounted) return;
    setState(() => _themeBusy = true);
    try {
      await _stopTheme();
      final path = await ThemeAudioService.extractEpisode(anime,
          anime.episodes[selection.$1], selection.$2, selection.$3);
      anime.themeAudioPath = path;
      await library.save();
      if (mounted) await _playTheme(force: true);
    } catch (e) {
      if (mounted) setState(() => _themeError = e.toString());
    } finally {
      if (mounted) setState(() => _themeBusy = false);
    }
  }

  Future<void> _themeOptions() async {
    await showModalBottomSheet<void>(context: context,
      isScrollControlled: true, backgroundColor: Palette.surface,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(
        child: Padding(padding: const EdgeInsets.all(18), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Text('Musique de présentation',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (anime.themeAudioPath != null)
              Text(p.basename(anime.themeAudioPath!), maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (_themeError != null)
              Text(_themeError!, style: const TextStyle(color: Colors.orangeAccent)),
            if (_themeBusy) const LinearProgressIndicator(),
            ListTile(leading: const Icon(Icons.audio_file),
              title: const Text('Importer un fichier audio'),
              onTap: _themeBusy ? null : () async {
                await _importThemeAudio();
                if (ctx.mounted) redraw(() {});
              }),
            if (Platform.isWindows && anime.episodes.isNotEmpty)
              ListTile(leading: const Icon(Icons.content_cut),
                title: const Text('Extraire un passage d’épisode (FFmpeg)'),
                onTap: _themeBusy ? null : () async {
                  // Fermer le panneau pour afficher correctement la sélection.
                  Navigator.pop(ctx);
                  await _extractThemeAudio();
                }),
            SwitchListTile(title: const Text('Démarrer avec la fiche'),
              value: anime.themeAutoplay, onChanged: (v) async {
                anime.themeAutoplay = v; await library.save();
                if (ctx.mounted) redraw(() {});
              }),
            SwitchListTile(title: const Text('Répéter en boucle'),
              value: anime.themeLoop, onChanged: (v) async {
                anime.themeLoop = v;
                await _themePlayer.setPlaylistMode(v
                    ? PlaylistMode.single : PlaylistMode.none);
                await library.save(); if (ctx.mounted) redraw(() {});
              }),
            Row(children: [const Icon(Icons.volume_down),
              Expanded(child: Slider(value: anime.themeVolume, min: 0, max: 100,
                onChanged: (v) {
                  anime.themeVolume = v;
                  unawaited(_themePlayer.setVolume(v));
                  redraw(() {});
                }, onChangeEnd: (_) => library.save())),
              Text('${anime.themeVolume.round()} %')]),
            if (anime.themeAudioPath != null) TextButton.icon(
              onPressed: () async {
                await _stopTheme();
                anime.themeAudioPath = null;
                await library.save();
                if (mounted) setState(() {});
                if (ctx.mounted) redraw(() {});
              }, icon: const Icon(Icons.music_off),
              label: const Text('Retirer la musique de cette fiche')),
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
          ]))),
      )),
    );
  }

  Future<void> _reloadGallery() async {
    final files = await CaptureGallery.list(anime);
    final priorities = anime.galleryOrder;
    files.sort((a, b) {
      final ia = priorities.indexOf(a);
      final ib = priorities.indexOf(b);
      if (ia < 0 && ib < 0) return a.compareTo(b);
      if (ia < 0) return 1;
      if (ib < 0) return -1;
      return ia.compareTo(ib);
    });
    if (!mounted) return;
    setState(() {
      _gallery = files;
      if (_galleryIndex >= files.length) _galleryIndex = 0;
    });
    _startSlideshow();
  }

  void _startSlideshow() {
    _slideshowTimer?.cancel();
    if (!anime.slideshowEnabled || _gallery.length < 2) return;
    _slideshowTimer = Timer.periodic(
      Duration(seconds: anime.slideshowSeconds.clamp(3, 60).toInt()), (_) {
        if (mounted && _gallery.length > 1) {
          setState(() => _galleryIndex = (_galleryIndex + 1) % _gallery.length);
        }
      });
  }

  // V28_HOTFIX_GALLERY_PARENS: fermeture du widget Expanded corrigée.
  Future<void> _galleryOptions() async {
    await _reloadGallery();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .86),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Text('Galerie et diaporama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${_gallery.length} captures sauvegardées'),
            if (Platform.isWindows)
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                onPressed: () async {
                  try {
                    final dir = await CaptureGallery.folder(anime);
                    await Process.start('explorer.exe', [dir.path], mode: ProcessStartMode.detached);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Impossible d’ouvrir le dossier : $e')));
                  }
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Ouvrir le dossier des captures'))),
            SwitchListTile(
              title: const Text('Activer le diaporama'),
              value: anime.slideshowEnabled,
              onChanged: _gallery.length < 2 ? null : (v) async {
                anime.slideshowEnabled = v;
                await library.save();
                if (!ctx.mounted) return;
                redraw(() {});
                setState(() {});
                _startSlideshow();
              },
            ),
            ListTile(title: const Text('Durée par image'),
              subtitle: Text('${anime.slideshowSeconds} secondes')),
            Slider(value: anime.slideshowSeconds.toDouble(), min: 3, max: 30,
              divisions: 27,
              onChanged: (v) => redraw(() => anime.slideshowSeconds = v.round()),
              onChangeEnd: (v) async {
                await library.save();
                _startSlideshow();
              }),
            if (_gallery.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Choisir le panorama, déplacer ou supprimer une capture :')),
              LayoutBuilder(builder: (ctx, constraints) {
                final columns = constraints.maxWidth >= 650 ? 3 :
                    constraints.maxWidth >= 390 ? 2 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _gallery.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, crossAxisSpacing: 10,
                    mainAxisSpacing: 10, mainAxisExtent: 196),
                  itemBuilder: (ctx, index) {
                    final path = _gallery[index];
                    return Card(clipBehavior: Clip.antiAlias,
                      color: Palette.ink,
                      child: Column(children: [
                        Expanded(child: InkWell(
                          onTap: () async {
                            anime.backdropLocalPath = path;
                            anime.backdropManual = true;
                            await library.save();
                            if (mounted) setState(() {});
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: SizedBox(width: double.infinity,
                            child: Image.file(File(path), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)))))),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          child: Text(p.basename(path), maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11))),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                          IconButton(icon: const Icon(Icons.arrow_back, size: 18),
                            tooltip: 'Vers la gauche', onPressed: index == 0 ? null : () async {
                              final item = _gallery.removeAt(index);
                              _gallery.insert(index - 1, item);
                              anime.galleryOrder = List<String>.from(_gallery);
                              await library.save();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                          IconButton(icon: const Icon(Icons.arrow_forward, size: 18),
                            tooltip: 'Vers la droite', onPressed: index == _gallery.length - 1 ? null : () async {
                              final item = _gallery.removeAt(index);
                              _gallery.insert(index + 1, item);
                              anime.galleryOrder = List<String>.from(_gallery);
                              await library.save();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                          IconButton(icon: const Icon(Icons.delete_outline, size: 18),
                            tooltip: 'Supprimer cette capture', onPressed: () async {
                              final ok = await showDialog<bool>(context: ctx,
                                builder: (dialogCtx) => AlertDialog(
                                  title: const Text('Supprimer cette capture ?'),
                                  content: Text(p.basename(path)), actions: [
                                    TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
                                      child: const Text('Annuler')),
                                    FilledButton(onPressed: () => Navigator.pop(dialogCtx, true),
                                      child: const Text('Supprimer')),
                                  ]));
                              if (ok != true) return;
                              final directory = await CaptureGallery.folder(anime);
                              if (!p.isWithin(directory.path, path)) return;
                              try { await File(path).delete(); } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Suppression impossible : $e')));
                                return;
                              }
                              if (anime.backdropLocalPath == path) {
                                anime.backdropLocalPath = null;
                                anime.backdropManual = false;
                              }
                              _gallery.remove(path);
                              anime.galleryOrder = List<String>.from(_gallery);
                              if (_gallery.length < 2) anime.slideshowEnabled = false;
                              _galleryIndex = 0;
                              await library.save();
                              _startSlideshow();
                              if (!ctx.mounted) return;
                              redraw(() {});
                              setState(() {});
                            }),
                        ]),
                      ]));
                  });
              }),
            ],
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
          ]),
        ),
      )),
    );
  }

  Anime get anime => widget.anime;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackdrop());
    unawaited(_reloadGallery());
    unawaited(_playTheme());
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _themeFade?.cancel();
    unawaited(_themePlayer.dispose());
    super.dispose();
  }

  Future<void> _loadBackdrop({bool force = false}) async {
    if (anime.backdropManual || anime.backdropLocalPath != null) return;
    if (!force && anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;
    final apiKey = library.settings.tmdbKey.trim();
    if (apiKey.isEmpty) {
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Renseigne ta clé TMDB dans les réglages pour chercher un panorama.'),
        ));
      }
      return;
    }
    if (force && mounted) setState(() => _working = true);
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      }.where((t) => t.trim().isNotEmpty);
      String? url;
      for (final title in titles) {
        url = await BackdropService.findBackdrop(title, apiKey);
        if (url != null) break;
      }
      if (!mounted) return;
      if (url != null) {
        anime.backdropUrl = url;
        await library.save();
        if (mounted) setState(() {});
      }
      if (force && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          url == null ? 'Aucun panorama fiable trouvé : affiche conservée.' : 'Panorama actualisé.'
        )));
      }
    } finally {
      if (force && mounted) setState(() => _working = false);
    }
  }

  Future<void> _chooseBackdrop() async {
    final key = library.settings.tmdbKey.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renseigne une clé TMDB dans les réglages pour choisir une image.'),
      ));
      return;
    }
    setState(() => _working = true);
    var candidates = <String>[];
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      };
      for (final title in titles.where((t) => t.trim().isNotEmpty)) {
        candidates = await BackdropService.findBackdrops(title, key);
        if (candidates.isNotEmpty) break;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun panorama disponible pour cette série.'),
      ));
      return;
    }
    // null : annuler; chaine vide : repasser en mode automatique.
    final selection = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Expanded(child: Text('Choisir un panorama',
                style: TextStyle(color: Palette.text, fontSize: 19,
                    fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, ''),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Revenir au panorama automatique'),
            )),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 800 ? 3 : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns, childAspectRatio: 16 / 10,
                crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final url = candidates[i];
                return InkWell(onTap: () => Navigator.pop(ctx, url),
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image))),
                    if (anime.backdropUrl == url)
                      const Align(alignment: Alignment.topRight,
                        child: Padding(padding: EdgeInsets.all(8),
                          child: Icon(Icons.check_circle, color: Colors.white))),
                  ]),
                );
              },
            );
          })),
        ]),
      )),
    );
    if (selection == null || !mounted) return;
    if (selection.isEmpty) {
      anime.backdropLocalPath = null;
      anime.backdropManual = false;
      anime.backdropUrl = null;
    } else {
      anime.backdropLocalPath = null;
      anime.backdropManual = true;
      anime.backdropUrl = selection;
    }
    await library.save();
    if (mounted) setState(() {});
    if (selection.isEmpty) unawaited(_loadBackdrop());
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() => _working = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _translate() async {
    await _run(() async {
      final ok = await library.translateOne(anime);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(anime.synopsisEn == null
                ? 'Pas de synopsis à traduire.'
                : (library.lastTranslateError ??
                    'Traduction indisponible. Vérifie le fournisseur dans les réglages.')),
          ),
        );
      }
    }, 'La traduction a échoué.');
  }

  Future<void> _searchAgain() async {
    final suggested = Scanner.titleFromFiles(anime.episodes);
    final controller = TextEditingController(
        text: suggested ?? anime.folderTitle);
    final query = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Corriger la fiche'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration(hintText: 'Titre à rechercher'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Chercher'),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty) return;

    setState(() => _working = true);
    // V23_AUTO_CATEGORY: matching searches all catalogs, including animated films.
    // Si la catégorie a été mal détectée, la correction doit aussi
    // proposer les résultats occidentaux (TMDB + TVmaze).
    final western = anime.category == 'western' || anime.category == 'adult';
    final primary = await MetadataService.searchMany(
      query,
      source: 'animation',
      tmdbKey: library.settings.tmdbKey,
    );
    final alternatives = western
        ? <AnimeMeta>[]
        : await MetadataService.searchMany(query, source: 'western',
            tmdbKey: library.settings.tmdbKey);
    final found = <AnimeMeta>[];
    final seen = <String>{};
    for (final result in [...primary, ...alternatives]) {
      final key = result.source + ':' + (result.sourceId?.toString() ?? result.title);
      if (seen.add(key)) found.add(result);
    }
    found.sort((a, b) => MetadataService.similarity(query, b.title)
        .compareTo(MetadataService.similarity(query, a.title)));
    final results = found.take(20).toList();
    if (!mounted) return;
    setState(() => _working = false);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun résultat pour ce titre.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<AnimeMeta>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final r = results[i];
          return ListTile(
            leading: r.imageUrl == null
                ? Icon(Icons.movie_outlined, color: Palette.muted)
                : SizedBox(
                    width: 40,
                    child: CachedNetworkImage(
                        imageUrl: r.imageUrl!, fit: BoxFit.cover)),
            title: Text(r.title, style: const TextStyle(fontSize: 14)),
            subtitle: Text(r.summaryLine,
                style: TextStyle(color: Palette.muted, fontSize: 12)),
            onTap: () => Navigator.pop(ctx, r),
          );
        },
      ),
    );
    if (chosen == null) return;

    await _run(() async {
      library.applyMeta(anime, chosen);
      library.manualIds.add(anime.id);
      library.remember(anime.folderTitle, chosen.titleRomaji ?? chosen.title);
      await library.save();
      if (library.settings.autoTranslate) {
        await library.translateOne(anime);
      }
      library.refresh();
    }, 'Impossible d\'appliquer la fiche.');
  }

  Future<void> _askAi() async {
    setState(() => _working = true);
    final message = await library.identifyWithAi(anime);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _adjustBackdrop() async {
    var x = anime.backdropAlignX;
    var y = anime.backdropAlignY;
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
        backgroundColor: Palette.surface,
        title: const Text('Cadrage du panorama'),
        content: SizedBox(width: 390, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (anime.backdropLocalPath != null && File(anime.backdropLocalPath!).existsSync())
              AspectRatio(aspectRatio: 16/9,
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: Image.file(File(anime.backdropLocalPath!), fit: BoxFit.cover,
                    alignment: Alignment(x, y))))
            else if (anime.backdropUrl != null)
              AspectRatio(aspectRatio: 16/9,
                child: ClipRRect(borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: anime.backdropUrl!, fit: BoxFit.cover,
                    alignment: Alignment(x, y),
                  ))),
            const SizedBox(height: 12),
            const Text('Deplacer horizontalement'),
            Slider(value: x, min: -1, max: 1,
              onChanged: (v) => refresh(() => x = v)),
            const Text('Deplacer verticalement'),
            Slider(value: y, min: -1, max: 1,
              onChanged: (v) => refresh(() => y = v)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => refresh(() {x=0; y=0;}),
            child: const Text('Centrer')),
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer')),
        ],
      )),
    );
    if (changed != true || !mounted) return;
    anime.backdropAlignX = x;
    anime.backdropAlignY = y;
    await library.save();
    if (mounted) setState(() {});
  }

  // V25_PANORAMA_LOCAL: copie perenne et validation des dimensions.
  Future<void> _importLocalBackdrop() async {
    if (_working) return;
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: false);
      if (selection == null || selection.files.isEmpty) return;
      final sourcePath = selection.files.single.path;
      if (sourcePath == null || sourcePath.isEmpty) throw const FormatException('Fichier inaccessible.');
      final source = File(sourcePath);
      if (!await source.exists()) throw const FormatException('Fichier introuvable.');
      if (await source.length() > 25 * 1024 * 1024) {
        throw const FormatException('Image trop volumineuse (maximum 25 Mo).');
      }
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (width < 960 || height < 540 || width / height < 1.3) {
        throw const FormatException('Choisis une image paysage de 960 × 540 minimum.');
      }
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'panoramas'));
      await dir.create(recursive: true);
      final extension = p.extension(source.path).toLowerCase();
      final name = 'panorama_${DateTime.now().microsecondsSinceEpoch}${extension}';
      final destination = File(p.join(dir.path, name));
      await destination.writeAsBytes(bytes, flush: true);
      final previous = anime.backdropLocalPath;
      anime.backdropLocalPath = destination.path;
      anime.backdropManual = true;
      anime.backdropAlignX = 0;
      anime.backdropAlignY = 0;
      await library.save();
      library.refresh();
      if (mounted) setState(() {});
      // Supprimer seulement une ancienne copie gérée par l’application.
      if (previous != null && p.isWithin(dir.path, previous)) {
        try { await File(previous).delete(); } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Panorama personnel enregistré.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import impossible : $e')));
    }
  }

  Future<void> _removeLocalBackdrop() async {
    final previous = anime.backdropLocalPath;
    anime.backdropLocalPath = null;
    anime.backdropManual = false;
    anime.backdropUrl = null;
    await library.save();
    library.refresh();
    if (mounted) setState(() {});
    if (previous != null) {
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'panoramas'));
      if (p.isWithin(dir.path, previous)) {
        try { await File(previous).delete(); } catch (_) {}
      }
    }
    unawaited(_loadBackdrop());
  }

  Widget _backgroundArt() {
    final position = Alignment(anime.backdropAlignX, anime.backdropAlignY);
    final local = anime.slideshowEnabled && _gallery.isNotEmpty
        ? _gallery[_galleryIndex] : anime.backdropLocalPath;
    Widget image;
    if (local != null && File(local).existsSync()) {
      image = Image.file(File(local), fit: BoxFit.cover,
          alignment: position, errorBuilder: (_, __, ___) => const SizedBox.shrink());
    } else if (anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) {
      image = CachedNetworkImage(imageUrl: anime.backdropUrl!, fit: BoxFit.cover,
          alignment: position, errorWidget: (_, __, ___) => const SizedBox.shrink());
    } else {
      // V25: aucune affiche verticale agrandie en faux panorama.
      image = const DecoratedBox(decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF192734), Color(0xFF10151D), Color(0xFF30202B)])));
    }
    return IgnorePointer(
      child: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 950),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand,
            children: [...previous, if (current != null) current]),
          child: SizedBox.expand(key: ValueKey<String>(
            local ?? anime.backdropUrl ?? 'fallback'), child: image),
        ),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0x77000000), Palette.ink.withOpacity(0.62),
                   Palette.ink.withOpacity(0.88)],
          stops: const [0.0, 0.45, 1.0],
        ))),
      ]),
    );
  }

  /// Les trois écritures du titre, quand elles sont connues.
  Widget _titleVariants() {
    final rows = <List<String>>[
      if (anime.romajiTitle != null && anime.romajiTitle!.isNotEmpty)
        ['Romaji', anime.romajiTitle!],
      if (anime.apiTitle != null && anime.apiTitle!.isNotEmpty)
        ['Anglais', anime.apiTitle!],
      if (anime.frenchTitle != null && anime.frenchTitle!.isNotEmpty)
        ['Français', anime.frenchTitle!],
      if (anime.nativeTitle != null && anime.nativeTitle!.isNotEmpty)
        ['日本語', anime.nativeTitle!],
    ];
    if (rows.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 3),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          collapsedBackgroundColor: Colors.transparent,
          backgroundColor: const Color(0x6611151C),
          iconColor: Palette.kin,
          collapsedIconColor: Palette.kin,
          title: Text('Titres et langues', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Palette.kin)),
          children: [for (final row in rows)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 72, child: Text(row[0],
                      style: TextStyle(color: Palette.muted, fontSize: 12))),
                  Expanded(child: SelectableText(row[1],
                      style: const TextStyle(fontSize: 13, height: 1.35))),
                ])),
          ],
        ),
      ),
    );
  }

  void _play(int index, {Duration at = Duration.zero}) {
    unawaited(_stopTheme());
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          title: anime.title,
          episodes: anime.episodes,
          startIndex: index,
          anime: anime,
          startAt: at,
        ),
      ),
    ).then((_) {
      if (mounted) {
        unawaited(_reloadGallery());
        unawaited(_playTheme());
      }
    });
  }

  /// Regroupe les episodes par saison, les bonus a part.
  Map<String, List<int>> _bySeason() {
    final groups = <String, List<int>>{};
    final multiSeason = anime.seasons.length > 1;

    for (var i = 0; i < anime.episodes.length; i++) {
      final e = anime.episodes[i];
      final label = e.bonus
          ? 'Bonus et hors-série'
          : (multiSeason ? 'Saison ${e.season ?? 1}' : 'Épisodes');
      groups.putIfAbsent(label, () => []).add(i);
    }
    return groups;
  }

  /// Petit bilan : trous dans la numérotation, doublons, contenus bonus.
  Widget _healthCard() {
    final issues = anime.issues;
    final twins = library.duplicatesOf(anime);
    if (issues.isEmpty && twins.isEmpty) return const SizedBox.shrink();

    final lines = <String>[];
    for (final t in twins) {
      lines.add('Également présent dans ${t.id}');
    }
    issues.missing.forEach((season, holes) {
      final where = anime.seasons.length > 1 ? 'saison $season : ' : '';
      final list = holes.take(12).join(', ');
      lines.add('Épisodes manquants — $where$list'
          '${holes.length > 12 ? '…' : ''}');
    });
    issues.duplicates.forEach((season, doubled) {
      final where = anime.seasons.length > 1 ? 'saison $season : ' : '';
      lines.add('En double — $where${doubled.join(', ')}');
    });
    if (issues.bonusCount > 0) {
      lines.add(
          '${issues.bonusCount} fichier${issues.bonusCount > 1 ? 's' : ''} bonus '
          '(OAV, génériques, making-of)');
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.line),
        borderRadius: BorderRadius.circular(radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 16, color: Palette.kin),
              SizedBox(width: 8),
              Text('État de la collection',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line,
                  style: TextStyle(
                      color: Palette.muted, fontSize: 12, height: 1.4)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final synopsis = _showOriginal ? anime.synopsisEn : anime.synopsis;
        final seasons = _bySeason();

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_immersiveBackground) _backgroundArt(),
              ScrollConfiguration(
            behavior: const TextPageScrollBehavior(),
            child: CustomScrollView(
            slivers: [
              _banner(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_working)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Palette.raised,
                              color: Palette.shu),
                        ),
                      _identityHeader(),
                      _resumeButton(),
                      const SizedBox(height: 16),
                      _badges(),
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _genres(),
                      ],
                      _titleVariants(),
                      const SizedBox(height: 18),
                      SelectableText(
                        synopsis == null || synopsis.isEmpty
                            ? 'Pas encore de synopsis. Utilise « Corriger la fiche » pour retrouver la série.'
                            : synopsis,
                        style: TextStyle(
                            height: 1.55, fontSize: 14.5, color: Palette.text),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                  width: 3, height: 16, color: Palette.shu),
                              const SizedBox(width: 8),
                              Text(
                                '${anime.episodes.length} épisodes',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => library.markAllWatched(
                                anime, !anime.finished),
                            child: Text(
                              anime.finished
                                  ? 'Tout marquer non vu'
                                  : 'Tout marquer vu',
                              style: TextStyle(
                                  color: Palette.muted, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              for (final entry in seasons.entries) ...[
                if (seasons.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                            color: Palette.kin,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _episodeTile(entry.value[i]),
                      childCount: entry.value.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _detailMenuAction(String action) async {
    if (_working && !['health', 'titles', 'original', 'background'].contains(action)) {
      return;
    }
    switch (action) {
      case 'health':
        final issues = anime.issues;
        final twins = library.duplicatesOf(anime);
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Etat de la collection'),
          content: SizedBox(
            width: 570,
            child: SingleChildScrollView(child:
              issues.isEmpty && twins.isEmpty
                ? const Text('Aucune anomalie detectee dans cette collection.')
                : _healthCard()),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'titles':
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          backgroundColor: Palette.surface,
          title: const Text('Titres et langues'),
          content: SingleChildScrollView(child: SizedBox(
            width: 540, child: _titleVariants())),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'))],
        ));
        break;
      case 'translate': await _translate(); break;
      case 'original': setState(() => _showOriginal = !_showOriginal); break;
      case 'background':
        setState(() => _immersiveBackground = !_immersiveBackground); break;
      case 'refresh': await _loadBackdrop(force: true); break;
      case 'choose': await _chooseBackdrop(); break;
      case 'gallery': await _galleryOptions(); break;
      case 'music': await _themeOptions(); break;
      case 'import_local': await _importLocalBackdrop(); break;
      case 'remove_local': await _removeLocalBackdrop(); break;
      case 'crop':
        if (anime.backdropUrl != null || anime.backdropLocalPath != null) await _adjustBackdrop();
        break;
      case 'correct': await _searchAgain(); break;
      case 'ai': await _askAi(); break;
      case 'category':
        if (!mounted) return;
        final chosen = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Palette.surface,
          builder: (ctx) => SafeArea(child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              ListTile(title: const Text('Anime japonais'),
                onTap: () => Navigator.pop(ctx, 'anime')),
              ListTile(title: const Text('Dessin anime'),
                onTap: () => Navigator.pop(ctx, 'western')),
              ListTile(title: const Text('Animation adulte'),
                onTap: () => Navigator.pop(ctx, 'adult')),
              // V24_UNIDENTIFIED: unknown files stay visible; allow manual override.
              ListTile(title: const Text('À identifier / autre animation'),
                onTap: () => Navigator.pop(ctx, 'other')),
            ],
          )),
        );
        if (chosen != null) {
          anime.category = chosen;
          await library.save();
          library.refresh();
        }
        break;
    }
  }

  // ---------------------------------------------------------------- bandeau

  // V20_IMMERSIVE : le panorama unique est celui du fond de la fiche.
  Widget _banner() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 54,
      backgroundColor: Palette.ink.withOpacity(0.66),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Text(anime.title, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      actions: [
        // V21_MENU_IMMERSIF: les reglages occasionnels quittent le panorama.
        PopupMenuButton<String>(
          tooltip: 'Informations et options de la fiche',
          icon: const Icon(Icons.more_vert),
          onSelected: _detailMenuAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'health', child: ListTile(
              dense: true, leading: Icon(Icons.fact_check_outlined),
              title: Text('Etat de la collection'))),
            PopupMenuItem(value: 'titles', child: ListTile(
              dense: true, leading: Icon(Icons.translate_outlined),
              title: Text('Titres et langues'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'translate', child: ListTile(
              dense: true, leading: Icon(Icons.translate),
              title: Text('Traduire la description'))),
            PopupMenuItem(value: 'original', child: ListTile(
              dense: true, leading: Icon(Icons.menu_book_outlined),
              title: Text('Voir original / traduction'))),
            PopupMenuItem(value: 'background', child: ListTile(
              dense: true, leading: Icon(Icons.wallpaper_outlined),
              title: Text('Changer le mode de fond'))),
            PopupMenuItem(value: 'refresh', child: ListTile(
              dense: true, leading: Icon(Icons.landscape_outlined),
              title: Text('Actualiser le panorama'))),
            PopupMenuItem(value: 'choose', child: ListTile(
              dense: true, leading: Icon(Icons.collections_outlined),
              title: Text('Choisir le panorama'))),
            PopupMenuItem(value: 'music', child: ListTile(
              dense: true, leading: Icon(Icons.library_music_outlined),
              title: Text('Musique de la fiche'))),
            PopupMenuItem(value: 'gallery', child: ListTile(
              dense: true, leading: Icon(Icons.photo_library_outlined),
              title: Text('Galerie et diaporama'))),
            PopupMenuItem(value: 'import_local', child: ListTile(
              dense: true, leading: Icon(Icons.add_photo_alternate_outlined),
              title: Text('Importer un panorama du disque'))),
            PopupMenuItem(value: 'remove_local', child: ListTile(
              dense: true, leading: Icon(Icons.restore),
              title: Text('Revenir au panorama automatique'))),
            PopupMenuItem(value: 'crop', child: ListTile(
              dense: true, leading: Icon(Icons.crop_free),
              title: Text('Ajuster le cadrage'))),
            PopupMenuDivider(),
            PopupMenuItem(value: 'category', child: ListTile(
              dense: true, leading: Icon(Icons.category_outlined),
              title: Text('Changer la categorie'))),
            PopupMenuItem(value: 'correct', child: ListTile(
              dense: true, leading: Icon(Icons.search),
              title: Text('Corriger la fiche'))),
            PopupMenuItem(value: 'ai', child: ListTile(
              dense: true, leading: Icon(Icons.auto_awesome),
              title: Text('Identifier avec l IA'))),
          ],
        ),
        if (anime.themeAudioPath != null) IconButton(
          tooltip: _themePlaying ? 'Couper la musique' : 'Lancer la musique',
          onPressed: _toggleTheme,
          icon: Icon(_themePlaying ? Icons.volume_up : Icons.music_note,
            color: Palette.kin)),
        IconButton(
          tooltip: 'Favori',
          onPressed: () => library.toggleFavorite(anime),
          icon: Icon(anime.favorite ? Icons.favorite : Icons.favorite_border,
              color: anime.favorite ? Palette.sakura : Colors.white),
        ),
      ],
    );
  }

  Widget _identityHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusMd),
            child: SizedBox(width: 82, height: 116,
                child: PosterImage(anime: anime, iconSize: 24)),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(anime.title, maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 25,
                    height: 1.12, fontWeight: FontWeight.w700)),
              if (anime.nativeTitle != null &&
                  anime.nativeTitle!.trim().isNotEmpty &&
                  anime.nativeTitle != anime.title) ...[
                const SizedBox(height: 5),
                Text(anime.nativeTitle!, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              ],
              if (anime.progress > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: anime.progress, minHeight: 3,
                  backgroundColor: const Color(0x55FFFFFF), color: Palette.kin),
                const SizedBox(height: 4),
                Text('${anime.watchedCount} / ${anime.episodes.length} épisodes vus',
                    style: TextStyle(color: Palette.muted, fontSize: 11)),
              ],
            ],
          )),
        ],
      ),
    );
  }

  Widget _resumeButton() {
    if (anime.episodes.isEmpty) return const SizedBox.shrink();
    final index = anime.resumeIndex;
    final at = anime.resumePosition;
    final label = anime.finished
        ? 'Revoir depuis le début'
        : (at > Duration.zero
            ? "Reprendre l'épisode ${index + 1}"
            : "Lire l'épisode ${index + 1}");
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => anime.finished ? _play(0) : _play(index, at: at),
        icon: Icon(Icons.play_arrow_rounded, color: Palette.kin, size: 22),
        label: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xB51A1C24),
          side: const BorderSide(color: Color(0xAAE5AF6D)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }

  Widget _badges() {
    final items = <List<String>>[
      if (anime.year != null) ['Année', '${anime.year}'],
      if (anime.type != null) ['Format', anime.type!],
      if (anime.score != null) ['Note', anime.score!.toStringAsFixed(2)],
      if (anime.status != null) ['Statut', anime.status!],
      if (anime.studios != null) ['Studio', anime.studios!],
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x99171D25),
              border: Border.all(color: const Color(0x50FFFFFF)),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item[0],
                    style: TextStyle(
                        color: Palette.muted,
                        fontSize: 9.5,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(item[1],
                    style: TextStyle(
                        color: item[0] == 'Note' ? Palette.kin : Palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _genres() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: anime.genres
          .map((g) => Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openGenre(g),
                  borderRadius: BorderRadius.circular(radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x73D6B86A)),
                      borderRadius: BorderRadius.circular(radiusSm),
                    ),
                    child: Text(g,
                        style: TextStyle(color: Palette.kin, fontSize: 12)),
                  ),
                ),
              ))
          .toList(),
    );
  }

  /// Un genre touché : les autres séries de la bibliothèque qui le
  /// portent, et un accès au catalogue filtré dessus.
  void _openGenre(String genre) {
    final others = library.animes
        .where((o) => o.id != anime.id && o.genres.contains(genre))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(genre,
                    style: TextStyle(
                        color: Palette.kin,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  others.isEmpty
                      ? 'Aucune autre série de ta bibliothèque ne porte ce genre.'
                      : '${others.length} autre(s) dans ta bibliothèque',
                  style: TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ),
              if (others.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: others.length,
                    itemBuilder: (_, i) {
                      final o = others[i];
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(radiusSm),
                          child: SizedBox(
                            width: 38,
                            height: 54,
                            child: PosterImage(anime: o, iconSize: 18),
                          ),
                        ),
                        title: Text(o.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: o.year == null
                            ? null
                            : Text('${o.year}',
                                style: TextStyle(
                                    color: Palette.muted, fontSize: 12)),
                        onTap: () {
                          Navigator.of(sheet).pop();
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => DetailScreen(anime: o)));
                        },
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: const Text('Voir ce genre dans le catalogue'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    GenreLinks.open(context, genre);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodeTile(int index) {
    final e = anime.episodes[index];
    final missing = !library.episodeExists(e);
    final seen = anime.isWatched(e);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: GestureDetector(
        onTap: () => library.setWatched(anime, e, !seen),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: seen ? Palette.kin : Colors.transparent,
            border: Border.all(color: seen ? Palette.kin : Palette.line),
            shape: BoxShape.circle,
          ),
          child: seen
              ? Icon(Icons.check, size: 16, color: Palette.ink)
              : Text(
                  e.bonus ? '★' : '${e.number ?? index + 1}',
                  style:
                      TextStyle(fontSize: 12, color: Palette.muted)),
        ),
      ),
      title: Text(
        e.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: missing || seen ? Palette.muted : Palette.text,
        ),
      ),
      subtitle: missing
          ? Text('Fichier introuvable',
              style: TextStyle(fontSize: 11.5, color: Palette.shu))
          : Row(
              children: [
                if (anime.episodeHasVf(e)) ...[
                  Text('VF',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Palette.kin)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Palette.muted)),
                ),
              ],
            ),
      trailing: Icon(Icons.play_circle_outline, color: Palette.muted),
      onTap: missing ? null : () => _play(index),
    );
  }
}
