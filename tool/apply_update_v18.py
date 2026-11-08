from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]

planned=[]
def edit(rel, operations):
    path=ROOT/rel
    s=path.read_text(encoding='utf-8')
    if 'V18_CREDITS' in s:
        print(f'Already applied: {rel}')
        return
    original=s
    for old,new in operations:
        count=s.count(old)
        if count!=1:
            raise RuntimeError(f'{rel}: expected one match, found {count}: {old[:85]!r}')
        s=s.replace(old,new,1)
    planned.append((path,s))
    print('Validated:',rel)

model_ops=[
('  /// Chemins des episodes deja regardes.','''  // V18_CREDITS: local credit markers, never change the source video.
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

  /// Chemins des episodes deja regardes.'''),
('    List<String>? watchedPaths,','    Map<String, Map<String, int>>? creditMarkers,\n    List<String>? watchedPaths,'),
('  })  : genres = genres ?? <String>[],','  })  : creditMarkers = creditMarkers ?? <String, Map<String, int>>{},\n        genres = genres ?? <String>[],'),
("        'watchedPaths': watchedPaths,","        'creditMarkers': creditMarkers,\n        'watchedPaths': watchedPaths,"),
("        watchedPaths:\n            (j['watchedPaths'] as List?)", "        creditMarkers: (j['creditMarkers'] as Map?)?.map((key, value) =>\n            MapEntry(key.toString(), (value as Map).map((k, v) =>\n                MapEntry(k.toString(), (v as num).toInt())))),\n        watchedPaths:\n            (j['watchedPaths'] as List?)"),
]
player_ops=[
('  bool _stopAtEnd = false;','''  // V18_CREDITS: optional marathon playback without opening/ending credits.
  bool _skipCredits = false;
  bool _advanceCreditsBusy = false;
  bool _introApplied = false;
  bool _creditScopeSeason = true;
  bool _stopAtEnd = false;'''),
('        _subtitleSearchDone = false;','''        _subtitleSearchDone = false;
        _introApplied = false;
        _advanceCreditsBusy = false;'''),
('      _checkSleep();\n    }));','''      _checkSleep();
      _checkCredits(p);
    }));'''),
('      if (!_seeked && d.inSeconds > 0 && widget.startAt.inSeconds > 5) {','''      if (!_seeked && d.inSeconds > 0 && widget.startAt.inSeconds > 5) {'''),
('    _loadExternalAudio();\n  }\n\n  void _flash','''    _loadExternalAudio();
    if (_skipCredits) _applyEndMode();
  }

  void _checkCredits(Duration position) {
    if (!_skipCredits || widget.anime == null || widget.episodes.isEmpty ||
        _stopAtEnd || _advanceCreditsBusy) return;
    if (_index < 0 || _index >= widget.episodes.length) return;
    final episode = widget.episodes[_index];
    final markers = widget.anime!.creditsFor(episode);
    if (markers == null) return;
    final intro = markers['introEnd'];
    final outro = markers['outroStart'];
    final current = position.inMilliseconds;
    // Only skip near the start. Never jump backward after seeking manually.
    if (!_introApplied && intro != null && intro >= 1000) {
      _introApplied = true;
      if (current <= intro && current <= 10000 &&
          (_duration == Duration.zero || intro < _duration.inMilliseconds - 3000)) {
        _player.seek(Duration(milliseconds: intro));
        return;
      }
    }
    if (outro == null || outro < 1000 || current < outro) return;
    if (_duration > Duration.zero && outro >= _duration.inMilliseconds - 2000) return;
    _advanceCreditsBusy = true;
    _persist(forceWatched: true);
    if (_index < widget.episodes.length - 1) {
      _player.next();
    } else {
      _player.pause();
      _flash('Saison terminée.');
    }
  }

  Future<void> _openCreditMarkers() async {
    final anime = widget.anime;
    if (anime == null || widget.episodes.isEmpty) {
      _flash('Repères disponibles uniquement pour les vidéos locales de la bibliothèque.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) {
        final episode = widget.episodes[_index];
        final key = _creditScopeSeason ? 's:${episode.season ?? 1}' : 'e:${episode.path}';
        final marks = anime.creditMarkers[key] ?? {};
        String time(int? ms) {
          if (ms == null) return 'Non défini';
          final s = ms ~/ 1000;
          return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
        }
        Future<void> mark(String marker) async {
          final ms = _position.inMilliseconds;
          if (ms <= 0 || (marker == 'outroStart' && _duration > Duration.zero &&
              ms >= _duration.inMilliseconds - 2000)) {
            _flash('Position non valide pour ce repère.'); return;
          }
          anime.setCreditMarker(episode, _creditScopeSeason, marker, ms);
          await library.save();
          library.refresh();
          if (ctx.mounted) refresh(() {});
        }
        return SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Repères de génériques', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Mets la vidéo en pause au bon endroit, puis enregistre le repère.',
                style: TextStyle(color: Palette.muted)),
              SwitchListTile(
                title: const Text('Appliquer à toute la saison'),
                subtitle: Text('Saison ${episode.season ?? 1}'),
                value: _creditScopeSeason,
                onChanged: (v) => refresh(() => _creditScopeSeason = v),
              ),
              Text('Fin du générique de début : ${time(marks['introEnd'])}'),
              FilledButton.icon(onPressed: () => mark('introEnd'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Marquer la fin du générique de début')),
              const SizedBox(height: 12),
              Text('Début du générique de fin : ${time(marks['outroStart'])}'),
              FilledButton.icon(onPressed: () => mark('outroStart'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Marquer le début du générique de fin')),
              TextButton.icon(onPressed: () async {
                anime.clearCreditMarkers(episode, _creditScopeSeason);
                await library.save();
                library.refresh();
                if (ctx.mounted) refresh(() {});
              }, icon: const Icon(Icons.restart_alt),
                label: const Text('Effacer les repères de cette portée')),
            ],
          ),
        ));
      }),
    );
  }

  void _flash'''),
("    final stop = _stopAtEnd || !library.settings.autoNext;","    final stop = _stopAtEnd || (!library.settings.autoNext && !_skipCredits);"),
("                  _optionTitle('À la fin de l\\'épisode'),", """                  _optionTitle('Marathon sans génériques'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enchaîner sans génériques'),
                    subtitle: const Text('Utilise les repères enregistrés. Aucun saut sans repère.'),
                    value: _skipCredits,
                    onChanged: (v) => update(() {
                      _skipCredits = v;
                      _introApplied = false;
                      _applyEndMode();
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _openCreditMarkers(); },
                    icon: const Icon(Icons.flag_outlined),
                    label: const Text('Définir les repères de génériques'),
                  ),

                  _optionTitle('À la fin de l\\'épisode'),"""),
]
# remove same-to-same no-op
player_ops=[(a,b) for a,b in player_ops if a!=b]
edit('lib/models/anime.dart',model_ops)
edit('lib/screens/player_screen.dart',player_ops)

for path,contents in planned:
    path.write_text(contents, encoding='utf-8')
    print('Updated:',path.relative_to(ROOT))
