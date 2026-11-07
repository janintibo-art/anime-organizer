#!/usr/bin/env python3
"""V32: ajoute une bande-son locale aux fiches, sans reconstruire le dépôt."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]

def replace_once(path, old, new):
    f = root / path
    src = f.read_text(encoding='utf-8')
    if old not in src:
        raise RuntimeError(f'Ancre manquante dans {path}: {old[:100]}')
    if src.count(old) != 1:
        raise RuntimeError(f'Ancre ambiguë dans {path}: {old[:90]}')
    f.write_text(src.replace(old, new, 1), encoding='utf-8')

model = 'lib/models/anime.dart'
replace_once(model,
    '  int slideshowSeconds = 8;\n',
    '''  int slideshowSeconds = 8;
  // V32: ambiance musicale personnelle, stockée séparément des épisodes.
  String? themeAudioPath;
  bool themeAutoplay = true;
  bool themeLoop = true;
  double themeVolume = 25.0;
''')
replace_once(model,
    '    this.slideshowSeconds = 8,\n',
    '''    this.slideshowSeconds = 8,
    this.themeAudioPath,
    this.themeAutoplay = true,
    this.themeLoop = true,
    this.themeVolume = 25.0,
''')
replace_once(model,
    "        'slideshowSeconds': slideshowSeconds,\n",
    """        'slideshowSeconds': slideshowSeconds,
        'themeAudioPath': themeAudioPath,
        'themeAutoplay': themeAutoplay,
        'themeLoop': themeLoop,
        'themeVolume': themeVolume,
""")
replace_once(model,
    "        slideshowSeconds: (j['slideshowSeconds'] as int? ?? 8).clamp(3, 60).toInt(),\n",
    """        slideshowSeconds: (j['slideshowSeconds'] as int? ?? 8).clamp(3, 60).toInt(),
        themeAudioPath: j['themeAudioPath'] as String?,
        themeAutoplay: j['themeAutoplay'] as bool? ?? true,
        themeLoop: j['themeLoop'] as bool? ?? true,
        themeVolume: (j['themeVolume'] as num? ?? 25).toDouble().clamp(0, 100).toDouble(),
""")

screen='lib/screens/detail_screen.dart'
replace_once(screen,
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:media_kit/media_kit.dart';\n")
replace_once(screen,
    "import '../services/capture_gallery.dart';\n",
    "import '../services/capture_gallery.dart';\nimport '../services/theme_audio_service.dart';\n")
replace_once(screen,
    "  Timer? _slideshowTimer;\n",
    """  Timer? _slideshowTimer;
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
""")
replace_once(screen,
    "    unawaited(_reloadGallery());\n  }\n\n  @override\n  void dispose() {",
    """    unawaited(_reloadGallery());
    unawaited(_playTheme());
  }

  @override
  void dispose() {""")
replace_once(screen,
    "    _slideshowTimer?.cancel();\n    super.dispose();",
    """    _slideshowTimer?.cancel();
    _themeFade?.cancel();
    unawaited(_themePlayer.dispose());
    super.dispose();""")
replace_once(screen,
    "  void _play(int index, {Duration at = Duration.zero}) {\n    Navigator.of(context).push(",
    """  void _play(int index, {Duration at = Duration.zero}) {
    unawaited(_stopTheme());
    Navigator.of(context).push(""")
replace_once(screen,
    "    ).then((_) { if (mounted) unawaited(_reloadGallery()); });",
    """    ).then((_) {
      if (mounted) {
        unawaited(_reloadGallery());
        unawaited(_playTheme());
      }
    });""")
replace_once(screen,
    "      case 'gallery': await _galleryOptions(); break;",
    "      case 'gallery': await _galleryOptions(); break;\n      case 'music': await _themeOptions(); break;")
replace_once(screen,
    "            PopupMenuItem(value: 'gallery', child: ListTile(",
    """            PopupMenuItem(value: 'music', child: ListTile(
              dense: true, leading: Icon(Icons.library_music_outlined),
              title: Text('Musique de la fiche'))),
            PopupMenuItem(value: 'gallery', child: ListTile(""")
replace_once(screen,
    "        IconButton(\n          tooltip: 'Favori',",
    """        if (anime.themeAudioPath != null) IconButton(
          tooltip: _themePlaying ? 'Couper la musique' : 'Lancer la musique',
          onPressed: _toggleTheme,
          icon: Icon(_themePlaying ? Icons.volume_up : Icons.music_note,
            color: Palette.kin)),
        IconButton(
          tooltip: 'Favori',""")
print('V32: modifications appliquées')
