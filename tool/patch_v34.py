#!/usr/bin/env python3
"""Correctif V34 : ancrages exacts, jamais de modification partielle en cas d'erreur."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
changes = {}

def load(path):
    return (root / path).read_text(encoding='utf-8-sig')

def replace(src, old, new, label):
    count = src.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: ancrage attendu une fois, trouve {count}. Aucun changement applique.')
    return src.replace(old, new, 1)

model_path = 'lib/models/anime.dart'
s = load(model_path)
s = replace(s, '  bool themeLoop = true;\n', "  bool themeLoop = true;\n  // V34: single, sequence ou shuffle.\n  String themePlayMode = 'single';\n", 'model champ')
s = replace(s, '    this.themeLoop = true,\n', "    this.themeLoop = true,\n    this.themePlayMode = 'single',\n", 'model constructeur')
s = replace(s, "        'themeLoop': themeLoop,\n", "        'themeLoop': themeLoop,\n        'themePlayMode': themePlayMode,\n", 'model json')
s = replace(s, "        themeLoop: j['themeLoop'] as bool? ?? true,\n", "        themeLoop: j['themeLoop'] as bool? ?? true,\n        themePlayMode: ['single', 'sequence', 'shuffle'].contains(j['themePlayMode'])\n            ? j['themePlayMode'] as String : 'single',\n", 'model lecture')
changes[model_path] = s

player_path = 'lib/screens/player_screen.dart'
s = load(player_path)
s = replace(s, "        _flash('F4 : extrait enregistre comme musique de la fiche !');", "        _flash('F4 : nouvel extrait conserve dans la bibliotheque musicale !');", 'player feedback')
s = replace(s, "content: Text('Musique enregistree ! Elle sera jouee sur la fiche de cet anime.'),", "content: Text('Nouvel extrait enregistre : ${p.basename(path)}'),", 'player notification')
changes[player_path] = s

detail_path = 'lib/screens/detail_screen.dart'
s = load(detail_path)
s = replace(s, "  String? _themeError;\n", "  String? _themeError;\n  StreamSubscription<bool>? _themeCompletedSubscription;\n  final _random = Random();\n  bool _themeAdvancing = false;\n  String? _currentThemeClip;\n", 'detail fields')
s = replace(s, "import 'dart:async';\n", "import 'dart:async';\nimport 'dart:math';\n", 'detail import random')
s = replace(s, "  Future<void> _playTheme({bool force = false}) async {\n    final path = anime.themeAudioPath;", "  Future<void> _playTheme({bool force = false, String? clip}) async {\n    final path = clip ?? anime.themeAudioPath;", 'detail lecture param')
s = replace(s, "      await _themePlayer.open(Media(Uri.file(path).toString()));", "      _currentThemeClip = path;\n      await _themePlayer.open(Media(Uri.file(path).toString()));", 'detail extrait courant')
s = replace(s, "          anime.themeLoop ? PlaylistMode.single : PlaylistMode.none);", "          anime.themePlayMode == 'single' && anime.themeLoop\n              ? PlaylistMode.single : PlaylistMode.none);", 'detail boucle')
anchor = '  Future<void> _toggleTheme() async {\n'
advance = '''  // V34 : le morceau suivant ne demarre que si la fiche est encore ouverte.
  Future<void> _advanceTheme() async {
    if (_themeAdvancing || !_themePlaying || anime.themePlayMode == 'single') return;
    _themeAdvancing = true;
    try {
      final tracks = await ThemeAudioService.listClips(anime);
      if (!mounted || tracks.isEmpty) return;
      final current = _currentThemeClip ?? anime.themeAudioPath;
      final index = tracks.indexOf(current ?? '');
      final next = anime.themePlayMode == 'shuffle' && tracks.length > 1
          ? tracks[(_random.nextInt(tracks.length - 1) + (index < 0 ? 0 : index + 1)) % tracks.length]
          : tracks[(index + 1) % tracks.length];
      await _playTheme(force: true, clip: next);
    } catch (e) {
      if (mounted) setState(() => _themeError = 'Lecture suivante impossible : $e');
    } finally {
      _themeAdvancing = false;
    }
  }

  Future<void> _audioLibraryOptions() async {
    final clips = await ThemeAudioService.listClips(anime);
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context,
      isScrollControlled: true, backgroundColor: Palette.surface,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .83),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
            const Text('Bibliothèque sonore', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text('${clips.length} extrait(s) conservé(s) dans le dossier de cet animé'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: anime.themePlayMode,
              decoration: const InputDecoration(labelText: 'Mode de lecture'),
              items: const [
                DropdownMenuItem(value: 'single', child: Text('Extrait choisi (fixe)')),
                DropdownMenuItem(value: 'sequence', child: Text('À la suite')),
                DropdownMenuItem(value: 'shuffle', child: Text('Aléatoire')),
              ], onChanged: (mode) async {
                if (mode == null) return;
                anime.themePlayMode = mode;
                await _themePlayer.setPlaylistMode(mode == 'single' && anime.themeLoop
                    ? PlaylistMode.single : PlaylistMode.none);
                await library.save();
                if (ctx.mounted) redraw(() {});
              }),
            const SizedBox(height: 10),
            if (clips.isEmpty) const ListTile(title: Text('Aucun extrait pour le moment'),
              subtitle: Text('Importe un morceau ou utilise F4 deux fois dans un épisode.')),
            for (final file in List<String>.from(clips))
              Card(child: ListTile(
                dense: true,
                leading: Icon(anime.themeAudioPath == file
                    ? Icons.radio_button_checked : Icons.music_note),
                title: Text(p.basename(file), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: anime.themeAudioPath == file
                    ? const Text('Extrait principal') : null,
                onTap: () async {
                  await _stopTheme();
                  anime.themeAudioPath = file;
                  await library.save();
                  if (mounted) await _playTheme(force: true);
                  if (ctx.mounted) redraw(() {});
                },
                trailing: PopupMenuButton<String>(
                  tooltip: 'Gérer cet extrait',
                  onSelected: (action) async {
                    if (action == 'rename') {
                      final controller = TextEditingController(
                          text: p.basenameWithoutExtension(file));
                      final name = await showDialog<String>(context: ctx,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Renommer l’extrait'),
                          content: TextField(controller: controller, autofocus: true,
                            decoration: const InputDecoration(labelText: 'Nom du morceau')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogCtx),
                                child: const Text('Annuler')),
                            FilledButton(onPressed: () => Navigator.pop(dialogCtx, controller.text),
                                child: const Text('Renommer')),
                          ],
                        ));
                      controller.dispose();
                      if (name == null || name.trim().isEmpty) return;
                      try {
                        if (anime.themeAudioPath == file) await _stopTheme();
                        final renamed = await ThemeAudioService.renameClip(anime, file, name);
                        if (anime.themeAudioPath == file) anime.themeAudioPath = renamed;
                        clips[clips.indexOf(file)] = renamed;
                        clips.sort();
                        await library.save();
                      } catch (e) {
                        if (mounted) setState(() => _themeError = '$e');
                      }
                    } else if (action == 'delete') {
                      final ok = await showDialog<bool>(context: ctx,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Supprimer cet extrait ?'),
                          content: Text(p.basename(file)), actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
                              child: const Text('Annuler')),
                            FilledButton(onPressed: () => Navigator.pop(dialogCtx, true),
                              child: const Text('Supprimer')),
                          ]));
                      if (ok != true) return;
                      try {
                        if (anime.themeAudioPath == file) await _stopTheme();
                        await ThemeAudioService.deleteClip(anime, file);
                        clips.remove(file);
                        if (anime.themeAudioPath == file) {
                          anime.themeAudioPath = clips.isEmpty ? null : clips.first;
                        }
                        await library.save();
                      } catch (e) {
                        if (mounted) setState(() => _themeError = '$e');
                      }
                    }
                    if (mounted) setState(() {});
                    if (ctx.mounted) redraw(() {});
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renommer')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
                ),
              )),
            const SizedBox(height: 10),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          ]),
        ),
      )),
    );
  }

'''
s = replace(s, anchor, advance+anchor, 'detail galerie musicale')
s = replace(s, "    unawaited(_playTheme());\n  }\n\n  @override\n  void dispose() {", "    _themeCompletedSubscription = _themePlayer.stream.completed.listen((done) {\n      if (done && mounted && _themePlaying) unawaited(_advanceTheme());\n    });\n    unawaited(_playTheme());\n  }\n\n  @override\n  void dispose() {", 'detail on complete')
s = replace(s, "    _themeFade?.cancel();\n    unawaited(_themePlayer.dispose());", "    _themeFade?.cancel();\n    _themeCompletedSubscription?.cancel();\n    unawaited(_themePlayer.dispose());", 'detail dispose')
s = replace(s, "            if (_themeBusy) const LinearProgressIndicator(),", "            if (_themeBusy) const LinearProgressIndicator(),\n            ListTile(leading: const Icon(Icons.library_music_outlined),\n              title: const Text('Bibliothèque des extraits'),\n              subtitle: const Text('Choisir, renommer, supprimer ou lire plusieurs morceaux'),\n              onTap: () async {\n                Navigator.pop(ctx);\n                await _audioLibraryOptions();\n              }),", 'detail options')
s = replace(s, "                await _themePlayer.setPlaylistMode(v\n                    ? PlaylistMode.single : PlaylistMode.none);", "                await _themePlayer.setPlaylistMode(v && anime.themePlayMode == 'single'\n                    ? PlaylistMode.single : PlaylistMode.none);", 'detail switch loop')
changes[detail_path] = s

# Verifie tous les ancrages avant de toucher au projet.
for path, content in changes.items():
    (root / path).parent.mkdir(parents=True, exist_ok=True)
for path, content in changes.items():
    (root / path).write_text(content, encoding='utf-8')
print('V34 : modele, lecteur et galerie sonore mis a jour.')
