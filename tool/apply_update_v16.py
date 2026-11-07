#!/usr/bin/env python3
"""V16: option transcodage mobile (FFmpeg facultatif), sans remplacer le lecteur local."""
from pathlib import Path
import sys

def replace_once(path, old, new):
    p=Path(path)
    text=p.read_text(encoding='utf-8')
    if new in text:
        print('Déjà installé:',path); return
    count=text.count(old)
    if count != 1: raise RuntimeError(f'{path}: ancrage attendu une fois, trouvé {count}: {old[:95]!r}')
    p.write_text(text.replace(old,new,1),encoding='utf-8')
    print('Mis à jour:',path)

server='tool/sync_server.py'
replace_once(server, 'import re\n', 'import re\nimport shutil\nimport subprocess\n')
replace_once(server, "            if route.startswith('/v1/stream/'):\n", "            if route.startswith('/v1/transcode/'):\n                self.transcode(route, query); return\n            if route.startswith('/v1/stream/'):\n")
replace_once(server, "        def log_message(self, fmt, *args):\n", '''        def transcode(self, route, query):
            # Transcodage temps réel : ne fournit jamais le chemin du fichier.
            # L'URL est signée et liée au même ticket que le streaming direct.
            m = re.fullmatch(r'/v1/transcode/(\\d+)/(\\d+)', route)
            if not m:
                self.reply(404, {'error': 'not_found'}); return
            try:
                series, episode = int(m.group(1)), int(m.group(2))
                expires = int(query.get('expires', ['0'])[0])
                signature = query.get('signature', [''])[0]
                now = int(time.time())
                if not now <= expires <= now + TICKET_LIFETIME:
                    self.reply(403, {'error': 'expired_ticket'}); return
                path = video_at(lib, series, episode)
                if path is None or not hmac.compare_digest(
                    signature, sign(token, series, episode, expires, path)):
                    self.reply(403, {'error': 'invalid_ticket'}); return
                quality = query.get('quality', ['720'])[0]
                if quality not in ('480', '720'):
                    self.reply(400, {'error': 'invalid_quality'}); return
                executable = Path(sys.executable).resolve().parent / 'ffmpeg.exe'
                ffmpeg = str(executable) if executable.is_file() else shutil.which('ffmpeg')
                if not ffmpeg:
                    self.reply(503, {'error': 'ffmpeg_unavailable'}); return
                # 480p/720p, débit limité. libx264 en premier, NVENC plus tard.
                height = int(quality)
                bitrate = '1200k' if height == 480 else '2500k'
                maxrate = '1600k' if height == 480 else '3300k'
                args = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin',
                    '-i', str(path), '-map', '0:v:0', '-map', '0:a:0?',
                    '-vf', f'scale=-2:min(ih\\,{height})',
                    '-c:v', 'libx264', '-preset', 'veryfast', '-b:v', bitrate,
                    '-maxrate', maxrate, '-bufsize', maxrate,
                    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k',
                    '-ac', '2', '-f', 'mpegts', 'pipe:1']
                proc = subprocess.Popen(args, stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
                try:
                    self.send_response(200)
                    self.send_header('Content-Type', 'video/mp2t')
                    self.send_header('Cache-Control', 'no-store')
                    self.send_header('Connection', 'close')
                    self.end_headers()
                    self.close_connection = True
                    while True:
                        chunk = proc.stdout.read(64 * 1024)
                        if not chunk: break
                        self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    pass
                finally:
                    if proc.poll() is None:
                        proc.terminate()
                        try: proc.wait(timeout=2)
                        except subprocess.TimeoutExpired: proc.kill()
                    if proc.stdout: proc.stdout.close()
            except (ValueError, OSError, subprocess.SubprocessError):
                # Ne jamais divulguer le chemin local dans la réponse.
                pass

        def log_message(self, fmt, *args):
''')
# sys.executable for PyInstaller bundled exe
replace_once(server, 'import secrets\n', 'import secrets\nimport sys\n')

screen='lib/screens/remote_episodes_screen.dart'
replace_once(screen, '  bool _busy = true;\n', "  bool _busy = true;\n  String _quality = 'direct';\n")
replace_once(screen, '      final url = _endpoint(path, {\n', '''      final requestedPath = _quality == 'direct'
          ? path : path.replaceFirst('/v1/stream/', '/v1/transcode/');
      final url = _endpoint(requestedPath, {
        if (_quality != 'direct') 'quality': _quality,
''')
replace_once(screen, '''        : ListView.builder(
            itemCount: _episodes.length,
''', '''        : Column(children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Text('Qualité : '),
                const SizedBox(width: 8),
                Expanded(child: DropdownButton<String>(isExpanded: true,
                  value: _quality,
                  items: const [
                    DropdownMenuItem(value: 'direct', child: Text('Originale (sans conversion)')),
                    DropdownMenuItem(value: '720', child: Text('720p mobile (FFmpeg)')),
                    DropdownMenuItem(value: '480', child: Text('480p économique (FFmpeg)')),
                  ],
                  onChanged: _busy ? null : (v) { if (v != null) setState(() => _quality = v); },
                )),
              ])),
            Expanded(child: ListView.builder(
            itemCount: _episodes.length,
''')
replace_once(screen, '''            }),
  );
}''', '''            })),
          ]),
  );
}''')
# remove potential invalid dart server error unescaped? no
print('V16: patches appliqués; lancer la compilation GitHub pour validation Flutter.')
