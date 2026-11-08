#!/usr/bin/env python3
"""Anime Organizer V26: patches atomiques, ancres verifiees, relancable."""
from pathlib import Path
import sys
root = Path(__file__).resolve().parent
changes = {}

def edit(rel, callback):
    path = root / rel
    old = path.read_text(encoding='utf-8')
    updated = callback(old)
    if not updated or 'V26_' not in updated:
        raise RuntimeError(f"Echec de preparation: {rel}")
    changes[path] = updated

def replace_once(s, needle, replacement):
    occurrences = s.count(needle)
    if occurrences != 1:
        raise RuntimeError(f"Ancre non unique / absente: {needle[:75]!r} ({occurrences})")
    return s.replace(needle, replacement, 1)

def model(s):
    if 'V26_SLIDESHOW' in s: return s
    s = replace_once(s, '  String? backdropLocalPath;',
        '  // V26_SLIDESHOW: preferences sauvegardees par fiche.\n'
        '  bool slideshowEnabled = false;\n'
        '  int slideshowSeconds = 8;\n'
        '  String? backdropLocalPath;')
    s = replace_once(s, '    this.backdropLocalPath,',
        '    this.backdropLocalPath,\n    this.slideshowEnabled = false,\n    this.slideshowSeconds = 8,')
    s = replace_once(s, "        'backdropLocalPath': backdropLocalPath,",
        "        'backdropLocalPath': backdropLocalPath,\n"
        "        'slideshowEnabled': slideshowEnabled,\n"
        "        'slideshowSeconds': slideshowSeconds,")
    s = replace_once(s, "        backdropLocalPath: j['backdropLocalPath'] as String?,",
        "        backdropLocalPath: j['backdropLocalPath'] as String?,\n"
        "        slideshowEnabled: j['slideshowEnabled'] as bool? ?? false,\n"
        "        slideshowSeconds: (j['slideshowSeconds'] as int? ?? 8).clamp(3, 60).toInt(),")
    return s

def player(s):
    if 'V26_F2_CAPTURE' in s: return s
    s = replace_once(s, "import '../services/poster_cache.dart';",
        "import '../services/poster_cache.dart';\nimport '../services/capture_gallery.dart';")
    needle = '  void _persist({bool forceWatched = false}) {'
    addition = '''  // V26_F2_CAPTURE: capture la trame video (sans l'interface du lecteur).
  bool _captureBusy = false;
  Future<void> _captureForGallery({bool useAsPanorama = false}) async {
    final anime = widget.anime;
    if (anime == null || widget.episodes.isEmpty || _captureBusy) return;
    _captureBusy = true;
    try {
      final bytes = await _player.screenshot();
      if (bytes == null || bytes.length < 1024) {
        if (mounted) _flash('Capture impossible pour cette video.');
        return;
      }
      final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
      final path = await CaptureGallery.save(anime, episode, bytes);
      if (useAsPanorama) {
        anime.backdropLocalPath = path;
        anime.backdropManual = true;
        anime.backdropAlignX = 0;
        anime.backdropAlignY = 0;
        await library.save();
      }
      library.refresh();
      if (mounted) _flash(useAsPanorama
          ? 'Capture enregistree et definie comme panorama.'
          : 'Capture enregistree : ${path.split(Platform.pathSeparator).last}');
    } catch (e) {
      if (mounted) _flash('Capture impossible : $e');
    } finally {
      _captureBusy = false;
    }
  }

'''
    s = replace_once(s, needle, addition + needle)
    s = replace_once(s,
        '    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {',
        '    // F2: raccourci Windows pour capturer directement la video.\n'
        '    if (key == LogicalKeyboardKey.f2) {\n'
        '      _captureForGallery();\n'
        '    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {')
    needle = "                  _optionTitle('Ajustement de l\\'image'),"
    insertion = '''                  if (widget.anime != null) ...[
                    _optionTitle('Captures de la serie'),
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx); _captureForGallery(); },
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Capturer vers la galerie (F2)'),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () { Navigator.pop(ctx); _captureForGallery(useAsPanorama: true); },
                      icon: const Icon(Icons.wallpaper_outlined),
                      label: const Text('Capturer comme panorama principal'),
                    ),
                  ],
'''
    s = replace_once(s, needle, insertion + needle)
    return s

def detail(s):
    if 'V26_GALLERY' in s: return s
    s = replace_once(s, "import '../services/backdrop_service.dart';",
        "import '../services/backdrop_service.dart';\nimport '../services/capture_gallery.dart';")
    s = replace_once(s, '  Anime get anime => widget.anime;', '''  // V26_GALLERY: les images sont conservees hors des fichiers video.
  List<String> _gallery = [];
  int _galleryIndex = 0;
  Timer? _slideshowTimer;

  Future<void> _reloadGallery() async {
    final files = await CaptureGallery.list(anime);
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

  Future<void> _galleryOptions() async {
    await _reloadGallery();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context, backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .82),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Text('Galerie et diaporama', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${_gallery.length} image(s) sauvegardee(s)'),
            SwitchListTile(
              title: const Text('Activer le diaporama'),
              value: anime.slideshowEnabled,
              onChanged: _gallery.length < 2 ? null : (v) async {
                anime.slideshowEnabled = v;
                await library.save();
                if (!ctx.mounted) return;
                redraw(() {});
                _startSlideshow();
              },
            ),
            ListTile(
              title: const Text('Duree de chaque image'),
              subtitle: Text('${anime.slideshowSeconds} secondes'),
            ),
            Slider(value: anime.slideshowSeconds.toDouble(), min: 3, max: 30,
              divisions: 27,
              onChanged: (v) => redraw(() => anime.slideshowSeconds = v.round()),
              onChangeEnd: (v) async {
                await library.save();
                _startSlideshow();
              }),
            if (_gallery.isNotEmpty) ...[
              const Text('Choisir une image principale :'),
              for (final path in _gallery)
                ListTile(
                  leading: Image.file(File(path), width: 80, height: 46, fit: BoxFit.cover),
                  title: Text(p.basename(path), maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    anime.backdropLocalPath = path;
                    anime.backdropManual = true;
                    await library.save();
                    if (!mounted) return;
                    setState(() {});
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ],
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer')),
          ]),
        ),
      )),
    );
  }

  Anime get anime => widget.anime;''')
    s = replace_once(s, '  void initState() {\n    super.initState();\n    unawaited(_loadBackdrop());\n  }',
        '  void initState() {\n    super.initState();\n    unawaited(_loadBackdrop());\n    unawaited(_reloadGallery());\n  }\n\n'
        '  @override\n  void dispose() {\n    _slideshowTimer?.cancel();\n    super.dispose();\n  }')
    s = replace_once(s, '    final local = anime.backdropLocalPath;\n    Widget image;',
        "    final local = anime.slideshowEnabled && _gallery.isNotEmpty\n"
        "        ? _gallery[_galleryIndex] : anime.backdropLocalPath;\n"
        '    Widget image;')
    s = replace_once(s, "      case 'import_local': await _importLocalBackdrop(); break;",
        "      case 'gallery': await _galleryOptions(); break;\n"
        "      case 'import_local': await _importLocalBackdrop(); break;")
    s = replace_once(s, "            PopupMenuItem(value: 'import_local', child: ListTile(",
        "            PopupMenuItem(value: 'gallery', child: ListTile(\n"
        "              dense: true, leading: Icon(Icons.photo_library_outlined),\n"
        "              title: Text('Galerie et diaporama'))),\n"
        "            PopupMenuItem(value: 'import_local', child: ListTile(")
    # Une capture faite dans le lecteur doit etre visible au retour a la fiche.
    s = replace_once(s, '''  void _play(int index, {Duration at = Duration.zero}) {
    Navigator.of(context).push(''', '''  void _play(int index, {Duration at = Duration.zero}) {
    Navigator.of(context).push(''') # follow-up below
    s = replace_once(s, '''          startAt: at,
        ),
      ),
    );
  }
''', '''          startAt: at,
        ),
      ),
    ).then((_) { if (mounted) unawaited(_reloadGallery()); });
  }
''')
    return s

try:
    edit('lib/models/anime.dart', model)
    edit('lib/screens/player_screen.dart', player)
    edit('lib/screens/detail_screen.dart', detail)
    # Pas de modification avant que TOUTES les ancres soient verifiees.
    for file, data in changes.items():
        temp = file.with_suffix(file.suffix + '.v26-tmp')
        temp.write_text(data, encoding='utf-8')
    for file in changes:
        file.with_suffix(file.suffix + '.v26-tmp').replace(file)
    print('V26 appliquee: modele, lecteur F2, galerie et diaporama.')
except Exception as exc:
    print(f'ERREUR: {exc}', file=sys.stderr)
    sys.exit(1)
