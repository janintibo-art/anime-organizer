#!/usr/bin/env python3
"""Anime Organizer V17: authenticated streaming capabilities and diagnostics.
Only patches known anchors; existing user libraries are never modified.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def update(relative, transform):
    path = ROOT / relative
    if not path.is_file():
        raise RuntimeError(f'Fichier introuvable : {relative}')
    original = path.read_text(encoding='utf-8')
    changed = transform(original)
    if changed == original:
        print('Déjà à jour :', relative)
    else:
        path.write_text(changed, encoding='utf-8')
        print('Mis à jour :', relative)


def replace_once(src, old, new, name):
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f'{name}: repère attendu une fois, trouvé {n}')
    return src.replace(old, new, 1)


def patch_server(s):
    if 'def stream_capabilities():' in s:
        return s
    anchor = 'def handler_factory(lib, token):'
    helper = '''def ffmpeg_binary():
    """Find FFmpeg bundled next to server.exe or installed in PATH."""
    bundled = Path(sys.executable).resolve().parent / 'ffmpeg.exe'
    if bundled.is_file():
        return str(bundled)
    local = Path(__file__).resolve().parent / 'ffmpeg.exe'
    if local.is_file():
        return str(local)
    return shutil.which('ffmpeg')


def stream_capabilities():
    executable = ffmpeg_binary()
    if not executable:
        return {'ffmpeg': False, 'mode': 'direct', 'qualities': ['direct'],
                'message': 'FFmpeg absent : lecture originale uniquement.'}
    try:
        probe = subprocess.run([executable, '-hide_banner', '-version'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=4,
            check=False, text=True)
        if probe.returncode != 0:
            raise OSError('ffmpeg failed')
    except (OSError, subprocess.TimeoutExpired):
        return {'ffmpeg': False, 'mode': 'direct', 'qualities': ['direct'],
                'message': 'FFmpeg indisponible : lecture originale uniquement.'}
    return {'ffmpeg': True, 'mode': 'transcoding',
            'qualities': ['direct', '720', '480'],
            'message': 'FFmpeg disponible : conversion 720p ou 480p possible.'}


'''
    s=replace_once(s,anchor,helper+anchor,'serveur insertion')
    s=replace_once(s,"'/v1/ticket'):","'/v1/ticket', '/v1/capabilities'):",'serveur routes')
    s=replace_once(s,"elif route == '/v1/library':\n                        self.reply(200, snapshot(lib))", "elif route == '/v1/library':\n                        self.reply(200, snapshot(lib))\n                    elif route == '/v1/capabilities':\n                        self.reply(200, stream_capabilities())",'serveur capacités')
    old="executable = Path(sys.executable).resolve().parent / 'ffmpeg.exe'\n                ffmpeg = str(executable) if executable.is_file() else shutil.which('ffmpeg')"
    s=replace_once(s,old,"ffmpeg = ffmpeg_binary()",'serveur FFmpeg')
    return s


def patch_remote(s):
    if '_loadCapabilities()' in s:
        return s
    s=replace_once(s,"  String _quality = 'direct';", "  String _quality = 'direct';\n  bool _ffmpegAvailable = false;\n  String _serverCapabilities = 'Vérification des qualités en cours…';",'app état')
    anchor='  Future<void> _load() async {'
    method='''  Future<void> _loadCapabilities() async {
    try {
      final response = await http.get(_endpoint('/v1/capabilities', {}),
          headers: {'X-Anime-Pair-Code': widget.pairCode})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ffmpegAvailable = data['ffmpeg'] == true;
        _serverCapabilities = '${data['message'] ?? 'État du serveur inconnu.'}';
        if (!_ffmpegAvailable) _quality = 'direct';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ffmpegAvailable = false;
        _quality = 'direct';
        _serverCapabilities = 'Diagnostic indisponible : seul le mode original est proposé.';
      });
    }
  }

'''
    s=replace_once(s,anchor,method+anchor,'app insertion')
    s=replace_once(s,"    _load();\n  }", "    _load();\n    _loadCapabilities();\n  }",'app init')
    s=replace_once(s,"""                  items: const [
                    DropdownMenuItem(value: 'direct', child: Text('Originale (sans conversion)')),
                    DropdownMenuItem(value: '720', child: Text('720p mobile (FFmpeg)')),
                    DropdownMenuItem(value: '480', child: Text('480p économique (FFmpeg)')),
                  ],""", """                  items: [
                    const DropdownMenuItem(value: 'direct', child: Text('Originale (sans conversion)')),
                    if (_ffmpegAvailable) const DropdownMenuItem(value: '720', child: Text('720p mobile (FFmpeg)')),
                    if (_ffmpegAvailable) const DropdownMenuItem(value: '480', child: Text('480p économique (FFmpeg)')),
                  ],""", 'app choix qualité')
    s=replace_once(s,"""              ])),
            Expanded(child: ListView.builder(""", """              ])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_serverCapabilities,
                style: TextStyle(color: _ffmpegAvailable ? Palette.muted : Palette.kin)),
            ),
            Expanded(child: ListView.builder(""", 'app message diagnostic')
    return s

if __name__ == '__main__':
    try:
        update('tool/sync_server.py', patch_server)
        update('lib/screens/remote_episodes_screen.dart', patch_remote)
        print('V17 appliquée. Vérifie la compilation GitHub Actions.')
    except Exception as exc:
        sys.exit(f'ÉCHEC V17 : {exc}')
