#!/usr/bin/env python3
"""V33: touches F4 audio + recherche du catalogue officiel AnimeThemes.
Patching only, no full-file overwrite. Fails if the repository changed unexpectedly.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[1]

def patch(rel, old, new):
    path = root / rel
    current = path.read_text(encoding='utf-8')
    if new in current:
        print(f'Deja applique: {rel}')
        return
    n = current.count(old)
    if n != 1:
        raise RuntimeError(f'Ancre {rel} attendue une fois, trouvee {n}: {old[:60]!r}')
    path.write_text(current.replace(old, new, 1), encoding='utf-8')
    print('Modifie', rel)

p = 'lib/screens/player_screen.dart'
patch(p,
    "import '../services/capture_gallery.dart';\n",
    "import '../services/capture_gallery.dart';\nimport '../services/theme_audio_service.dart';\n")
patch(p,
    "  bool _captureBusy = false;\n",
    """  bool _captureBusy = false;
  // V33: marqueurs de debut/fin, enregistrés sur le fichier video courant.
  Duration? _audioMarkStart;
  String? _audioMarkEpisodePath;
  bool _audioExportBusy = false;

  Future<void> _markAudioF4() async {
    final anime = widget.anime;
    if (!Platform.isWindows || anime == null || widget.episodes.isEmpty) {
      if (mounted) _flash('F4 : extraction disponible pour les épisodes locaux sur Windows.');
      return;
    }
    if (_audioExportBusy) {
      if (mounted) _flash('Extraction audio en cours...');
      return;
    }
    final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
    final now = _player.state.position;
    final begin = _audioMarkStart;
    if (begin == null || _audioMarkEpisodePath != episode.path) {
      setState(() {
        _audioMarkStart = now;
        _audioMarkEpisodePath = episode.path;
      });
      _flash('F4 : debut memorise a ${_formatAudioTime(now)}. F4 pour terminer.');
      return;
    }
    if (now <= begin || now - begin > const Duration(minutes: 5)) {
      _flash('F4 : choisis une fin apres le debut (5 min maximum).');
      return;
    }
    setState(() {
      _audioMarkStart = null;
      _audioMarkEpisodePath = null;
      _audioExportBusy = true;
    });
    _flash('F4 : extraction MP3 en cours...');
    try {
      final path = await ThemeAudioService.extractEpisode(anime, episode, begin, now);
      anime.themeAudioPath = path;
      await library.save();
      library.refresh();
      if (mounted) {
        _flash('F4 : extrait enregistre comme musique de la fiche !');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Musique enregistree ! Elle sera jouee sur la fiche de cet anime.'),
        ));
      }
    } catch (e) {
      if (mounted) _flash('F4 : extraction impossible : $e');
    } finally {
      if (mounted) setState(() => _audioExportBusy = false);
    }
  }

  String _formatAudioTime(Duration value) {
    final m = value.inMinutes.toString().padLeft(2, '0');
    final s = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
""")
patch(p,
    "        _index = event.index;\n        _position = Duration.zero;",
    "        _index = event.index;\n        _audioMarkStart = null;\n        _audioMarkEpisodePath = null;\n        _position = Duration.zero;")
patch(p,
    "    if (key == LogicalKeyboardKey.f3) {\n      unawaited(_captureForGallery(useAsPanorama: true));\n      return true;\n    }\n    return false;",
    "    if (key == LogicalKeyboardKey.f3) {\n      unawaited(_captureForGallery(useAsPanorama: true));\n      return true;\n    }\n    if (key == LogicalKeyboardKey.f4) {\n      unawaited(_markAudioF4());\n      return true;\n    }\n    return false;")
patch(p,
    "    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {",
    "    } else if (key == LogicalKeyboardKey.f4) {\n      if (!Platform.isWindows) unawaited(_markAudioF4());\n    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {")
patch(p,
    "                  if (_notice != null)\n                    Positioned(",
    """                  if (_audioMarkStart != null)
                    Positioned(
                      top: 65,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xE67C2418),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('● F4 début ${_formatAudioTime(_audioMarkStart!)} · F4 pour terminer',
                          style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  if (_notice != null)
                    Positioned(""")
patch(p,
    "                      label: const Text('Capturer comme panorama principal (F3)'),\n                    ),",
    """                      label: const Text('Capturer comme panorama principal (F3)'),
                    ),
                    if (Platform.isWindows) ...[
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: () { Navigator.pop(ctx); unawaited(_markAudioF4()); },
                        icon: const Icon(Icons.music_note_outlined),
                        label: const Text('F4 : marquer début / fin du générique audio'),
                      ),
                    ],""")

p = 'lib/screens/detail_screen.dart'
patch(p,
    "import 'package:media_kit/media_kit.dart';\n",
    "import 'package:media_kit/media_kit.dart';\nimport 'package:url_launcher/url_launcher.dart';\n")
patch(p,
    "import '../services/theme_audio_service.dart';\n",
    "import '../services/theme_audio_service.dart';\nimport '../services/anime_themes_catalog.dart';\n")
patch(p,
    "  Future<void> _themeOptions() async {\n",
    """  // V33: identification des génériques via AnimeThemes.moe.
  // On affiche les metadonnees et le lien officiel : pas de telechargement
  // automatique de fichiers tiers sous droits.
  Future<void> _findThemesOnline() async {
    final titles = <String>{
      if (anime.romajiTitle != null) anime.romajiTitle!,
      if (anime.apiTitle != null) anime.apiTitle!,
      anime.folderTitle,
    }.where((v) => v.trim().isNotEmpty).toList();
    if (titles.isEmpty) return;
    setState(() => _themeBusy = true);
    List<AnimeThemeMatch> matches = [];
    try {
      for (final title in titles) {
        matches = await AnimeThemesCatalog.search(title);
        if (matches.isNotEmpty) break;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recherche AnimeThemes impossible : $e')));
    } finally {
      if (mounted) setState(() => _themeBusy = false);
    }
    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun générique trouvé dans AnimeThemes.')));
      return;
    }
    final picked = await showDialog<AnimeThemeMatch>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choisir la série AnimeThemes'),
        content: SizedBox(width: 460, height: 370,
          child: ListView(children: [for (final item in matches)
            ListTile(title: Text(item.name), subtitle: Text(item.year?.toString() ?? ''),
              onTap: () => Navigator.pop(ctx, item))])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'))],
      ));
    if (picked == null || !mounted) return;
    List<AnimeThemeEntry> songs = [];
    try {
      songs = await AnimeThemesCatalog.themes(picked.slug);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Génériques indisponibles : $e')));
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Génériques · ${picked.name}'),
      content: SizedBox(width: 470, height: 350, child: ListView(children: [
        if (songs.isEmpty) const Text('Liste indisponible. Consulte le catalogue.'),
        for (final song in songs)
          ListTile(leading: const Icon(Icons.music_note),
            title: Text('${song.label} · ${song.title}')),
        const Padding(padding: EdgeInsets.all(12), child: Text(
          'Le catalogue identifie les génériques. Pour utiliser une musique sur la fiche, importe ton propre audio ou extrais un épisode avec F4.')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        FilledButton(onPressed: () async {
          final uri = Uri.https('animethemes.moe', '/anime/${picked.slug}');
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }, child: const Text('Ouvrir AnimeThemes')),
      ],
    ));
  }

  Future<void> _themeOptions() async {
""")
patch(p,
    "            ListTile(leading: const Icon(Icons.audio_file),\n",
    """            ListTile(leading: const Icon(Icons.search),
              title: const Text('Rechercher automatiquement les génériques'),
              subtitle: const Text('Catalogue AnimeThemes · OP et ED'),
              onTap: _themeBusy ? null : () async {
                Navigator.pop(ctx);
                await _findThemesOnline();
              }),
            ListTile(leading: const Icon(Icons.audio_file),
""")
print('V33 appliquée : F4 et recherche AnimeThemes (métadonnées).')
