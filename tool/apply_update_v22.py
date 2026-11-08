from pathlib import Path
import re,py_compile
root=Path(__file__).resolve().parents[1]
changes={}
def replace(path, old, new):
 p=root/path
 s=changes.get(path,p.read_text(encoding='utf-8'))
 if new in s: return
 n=s.count(old)
 if n!=1: raise RuntimeError(f'{path}: emplacement absent ou ambigu ({n}) : {old[:90]!r}')
 changes[path]=s.replace(old,new,1)

srv='tool/sync_server.py'
replace(srv,'import json\n','import json\nimport threading\n')
replace(srv,'TICKET_LIFETIME = 6 * 3600','TICKET_LIFETIME = 6 * 3600\nPROGRESS_LOCK = threading.Lock()\n')
replace(srv,'def handler_factory(lib, token):','''def progress_file(lib):
    return Path(str(lib) + '.remote_progress.json')

def read_progress(lib):
    try:
        payload = json.loads(progress_file(lib).read_text(encoding='utf-8'))
        if isinstance(payload, dict): return payload
    except (OSError, ValueError, TypeError):
        pass
    return {}

def write_progress(lib, key, event):
    with PROGRESS_LOCK:
        values = read_progress(lib)
        values[key] = event
        target = progress_file(lib)
        temporary = Path(str(target) + '.tmp')
        temporary.write_text(json.dumps(values, ensure_ascii=False), encoding='utf-8')
        os.replace(temporary, target)

def handler_factory(lib, token):''')
replace(srv,"            if route in ('/v1/ping', '/v1/library', '/v1/episodes', '/v1/ticket', '/v1/capabilities'):","            if route in ('/v1/ping', '/v1/library', '/v1/episodes', '/v1/ticket', '/v1/capabilities'):")
replace(srv,"                        if route == '/v1/episodes':\n                            self.reply(200, {'episodes': [",'''                        if route == '/v1/episodes':
                            progress = read_progress(lib)
                            folder = str(catalog[series].get('folderTitle', ''))
                            self.reply(200, {'episodes': [''')
replace(srv,"                                 'bonus': bool(e.get('bonus', False)),",'''                                 'bonus': bool(e.get('bonus', False)),
                                 'resumeMs': progress.get(json.dumps([folder, e.get('season') or 1, e.get('number'), e.get('name')], ensure_ascii=False), {}).get('positionMs', 0),
                                 'watchedRemote': progress.get(json.dumps([folder, e.get('season') or 1, e.get('number'), e.get('name')], ensure_ascii=False), {}).get('watched', False),''')
replace(srv,'        def do_HEAD(self):','''        def do_POST(self):
            if urlsplit(self.path).path != '/v1/progress':
                self.reply(404, {'error': 'not_found'}); return
            if not self.authorized():
                self.reply(401, {'error': 'invalid_pairing_code'}); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 1 <= length <= 4096:
                    self.reply(413, {'error': 'invalid_size'}); return
                incoming = json.loads(self.rfile.read(length).decode('utf-8'))
                series = incoming.get('series')
                episode = incoming.get('episode')
                position = incoming.get('positionMs')
                duration = incoming.get('durationMs')
                if not all(type(v) is int for v in (series, episode, position, duration)):
                    raise ValueError('invalid types')
                if not (0 <= position <= 86400000 and 0 <= duration <= 86400000):
                    raise ValueError('invalid time')
                catalog = read_library(lib)
                if not (0 <= series < len(catalog)):
                    self.reply(404, {'error': 'series_not_found'}); return
                a = catalog[series]
                videos = a.get('episodes', [])
                if not (0 <= episode < len(videos)):
                    self.reply(404, {'error': 'episode_not_found'}); return
                e = videos[episode]
                folder = str(a.get('folderTitle') or '')
                season, number = e.get('season') or 1, e.get('number')
                key = json.dumps([folder, season, number, e.get('name')], ensure_ascii=False)
                watched = bool(incoming.get('completed') is True or
                    (duration > 0 and position / duration >= .92))
                record = {'folderTitle': folder, 'season': season,
                    'number': number, 'name': e.get('name'),
                    'positionMs': 0 if watched else position,
                    'durationMs': duration, 'watched': watched,
                    'updatedAtMs': int(time.time() * 1000)}
                with PROGRESS_LOCK:
                    previous = read_progress(lib).get(key, {})
                if previous.get('watched') is True: record['watched'] = True
                write_progress(lib, key, record)
                self.reply(200, {'saved': True})
            except (ValueError, TypeError, KeyError, UnicodeError, OSError):
                self.reply(400, {'error': 'invalid_progress'})

        def do_HEAD(self):''')
# player callback
pl='lib/screens/player_screen.dart'
replace(pl,'  final Duration startAt;','  final Duration startAt;\n  final Future<void> Function(Duration position, Duration duration, bool completed)? onRemoteProgress;')
replace(pl,'    this.startAt = Duration.zero,','    this.startAt = Duration.zero,\n    this.onRemoteProgress,')
replace(pl,'  void _persist({bool forceWatched = false}) {\n    final item = widget.anime;', '''  void _persist({bool forceWatched = false}) {
    if (widget.onRemoteProgress != null && widget.episodes.isNotEmpty) {
      unawaited(widget.onRemoteProgress!(
        forceWatched ? _duration : _position, _duration, forceWatched));
    }
    final item = widget.anime;''')
# remote screen
rm='lib/screens/remote_episodes_screen.dart'
replace(rm,"      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(",'''      final resume = episode['resumeMs'] is int ? episode['resumeMs'] as int : 0;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(''')
replace(rm,"        title: widget.seriesTitle,\n        episodes: [Episode(path: url,",'''        title: widget.seriesTitle,
        startAt: Duration(milliseconds: resume > 0 ? resume : 0),
        onRemoteProgress: (position, duration, completed) async {
          try {
            await http.post(_endpoint('/v1/progress', {}),
              headers: {'X-Anime-Pair-Code': widget.pairCode,
                        'Content-Type': 'application/json'},
              body: jsonEncode({'series': widget.seriesId, 'episode': index,
                'positionMs': position.inMilliseconds,
                'durationMs': duration.inMilliseconds, 'completed': completed}),
            ).timeout(const Duration(seconds: 6));
          } catch (_) { /* Une perte réseau ne doit pas interrompre le lecteur. */ }
        },
        episodes: [Episode(path: url,''')
replace(rm,"                subtitle: Text('Saison ${season ?? 1} · Épisode ${number ?? i + 1}'),",'''                subtitle: Text('Saison ${season ?? 1} · Épisode ${number ?? i + 1}'
                  '${e['watchedRemote'] == true ? ' · Vu sur téléphone' :
                    (e['resumeMs'] is int && (e['resumeMs'] as int) > 0 ? ' · Reprise disponible' : '')}'),''')
# Windows manual import
pc='lib/screens/pc_sync_screen.dart'
replace(pc,'  @override\n  void dispose() {','''  Future<void> _importRemotePlayback() async {
    if (!Platform.isWindows || _busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getApplicationSupportDirectory();
      final path = p.join(dir.path, 'library.json.remote_progress.json');
      final file = File(path);
      if (!file.existsSync()) {
        _message = 'Aucune progression Android à importer.';
        return;
      }
      final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      var imported = 0;
      for (final value in payload.values) {
        if (value is! Map) continue;
        final folder = '${value['folderTitle'] ?? ''}';
        final matches = library.animes.where((a) => a.folderTitle == folder).toList();
        if (matches.length != 1) continue;
        final item = matches.single;
        final candidates = item.episodes.where((e) =>
          (e.season ?? 1) == value['season'] && e.number == value['number'] &&
          e.name == value['name']).toList();
        if (candidates.length != 1) continue;
        final episode = candidates.single;
        final updated = value['updatedAtMs'];
        if (updated is! int || updated <= (item.lastPlayedAtMs ?? 0)) continue;
        final watched = value['watched'] == true;
        final position = value['positionMs'];
        if (position is! int || position < 0) continue;
        item.lastEpisodePath = episode.path;
        item.lastPositionMs = watched ? 0 : position;
        item.lastPlayedAtMs = updated;
        if (watched && !item.watchedPaths.contains(episode.path)) {
          item.watchedPaths.add(episode.path);
        }
        imported++;
      }
      if (imported > 0) {
        await library.save();
        library.refresh();
      }
      _message = '$imported progression(s) Android importée(s) sur Windows.';
    } catch (e) {
      _message = 'Import impossible : $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {''')
replace(pc,"          const SizedBox(height: 16),\n          FilledButton.icon(\n            onPressed: _busy ? null : (_server == null ? _start : () {",'''          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importRemotePlayback,
            icon: const Icon(Icons.download_done),
            label: const Text('Importer les lectures effectuées sur Android'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : (_server == null ? _start : () {''')
for path,data in changes.items():
 (root/path).write_text(data,encoding='utf-8')
 print('Updated:',path)
