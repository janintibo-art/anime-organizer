"""Anime Organizer companion: personal LAN/Tailscale streaming, stdlib only.
No public deployment: pair codes travel over HTTP; use trusted LAN or Tailscale.
"""
import argparse
import hashlib
import hmac
import json
import threading
import mimetypes
import os
import re
import shutil
import subprocess
import secrets
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v', '.wmv', '.flv', '.ts', '.mpeg', '.mpg'}
MAX_CHUNK = 512 * 1024
MAX_RANGE = 50 * 1024 * 1024
TICKET_LIFETIME = 6 * 3600
PROGRESS_LOCK = threading.Lock()



def read_library(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f).get('animes', [])


def episode_identity(e):
    season = e.get('season') if isinstance(e.get('season'), int) else 1
    number = e.get('number') if isinstance(e.get('number'), int) else None
    return f'{season}:{number}' if number is not None else None


def snapshot(path):
    titles = []
    for index, a in enumerate(read_library(path)):
        episodes = a.get('episodes', [])
        watched = set(a.get('watchedPaths', []))
        viewed = sorted({episode_identity(e) for e in episodes
                         if not e.get('bonus') and e.get('path') in watched
                         and episode_identity(e) is not None})
        titles.append({
            'id': index,
            'title': a.get('apiTitle') or a.get('folderTitle') or '',
            'folderTitle': a.get('folderTitle') or '',
            'romajiTitle': a.get('romajiTitle') or '',
            'nativeTitle': a.get('nativeTitle') or '',
            'frenchTitle': a.get('frenchTitle') or '',
            'episodeCount': len(episodes),
            'watchedCount': len(watched.intersection(e.get('path') for e in episodes)),
            'watchedKeys': viewed,
            'favorite': bool(a.get('favorite', False)),
            'imageUrl': a.get('imageUrl') or '',
        })
    return {'version': 2, 'libraryName': 'Anime Organizer PC', 'series': titles}


def video_at(lib, series, episode):
    catalog = read_library(lib)
    if not (0 <= series < len(catalog)):
        return None
    videos = catalog[series].get('episodes', [])
    if not (0 <= episode < len(videos)):
        return None
    item = videos[episode]
    filename = item.get('path', '')
    if not isinstance(filename, str) or Path(filename).suffix.lower() not in VIDEO_EXTENSIONS:
        return None
    path = Path(filename)
    if not path.is_file():
        return None
    return path


def sign(secret, series, episode, expires, path):
    data = f'{series}:{episode}:{expires}:{path}'.encode('utf-8')
    return hmac.new(secret.encode('utf-8'), data, hashlib.sha256).hexdigest()


def ffmpeg_binary():
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


def progress_file(lib):
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

def handler_factory(lib, token):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def authorized(self):
            return hmac.compare_digest(self.headers.get('X-Anime-Pair-Code', ''), token)

        def reply(self, status, payload):
            content = json.dumps(payload, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(content)

        def do_GET(self):
            parsed = urlsplit(self.path)
            route = parsed.path
            query = parse_qs(parsed.query)
            if route in ('/v1/ping', '/v1/library', '/v1/episodes', '/v1/ticket', '/v1/capabilities'):
                if not self.authorized():
                    self.reply(401, {'error': 'invalid_pairing_code'}); return
                try:
                    if route == '/v1/ping':
                        self.reply(200, {'service': 'Anime Organizer', 'version': 2, 'streaming': True})
                    elif route == '/v1/library':
                        self.reply(200, snapshot(lib))
                    elif route == '/v1/capabilities':
                        self.reply(200, stream_capabilities())
                    else:
                        series = int(query.get('series', ['-1'])[0])
                        catalog = read_library(lib)
                        if not 0 <= series < len(catalog):
                            self.reply(404, {'error': 'series_not_found'}); return
                        episodes = catalog[series].get('episodes', [])
                        if route == '/v1/episodes':
                            progress = read_progress(lib)
                            folder = str(catalog[series].get('folderTitle', ''))
                            self.reply(200, {'episodes': [
                                {'id': i, 'name': str(e.get('name', 'Épisode'))[:240],
                                 'season': e.get('season'), 'number': e.get('number'),
                                 'bonus': bool(e.get('bonus', False)),
                                 'resumeMs': progress.get(json.dumps([folder, e.get('season') or 1, e.get('number'), e.get('name')], ensure_ascii=False), {}).get('positionMs', 0),
                                 'watchedRemote': progress.get(json.dumps([folder, e.get('season') or 1, e.get('number'), e.get('name')], ensure_ascii=False), {}).get('watched', False),
                                 'available': Path(e.get('path', '')).is_file()
                                 and Path(e.get('path', '')).suffix.lower() in VIDEO_EXTENSIONS}
                                for i, e in enumerate(episodes)]})
                        else:
                            episode = int(query.get('episode', ['-1'])[0])
                            path = video_at(lib, series, episode)
                            if path is None:
                                self.reply(404, {'error': 'video_unavailable'}); return
                            expires = int(time.time()) + TICKET_LIFETIME
                            signature = sign(token, series, episode, expires, path)
                            self.reply(200, {'path': f'/v1/stream/{series}/{episode}',
                                'expires': expires, 'signature': signature})
                except (OSError, ValueError, TypeError, IndexError):
                    self.reply(503, {'error': 'library_unavailable'})
                return
            if route.startswith('/v1/transcode/'):
                self.transcode(route, query); return
            if route.startswith('/v1/stream/'):
                self.stream(route, query, head=False)
                return
            self.reply(404, {'error': 'not_found'})

        def do_POST(self):
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

        def do_HEAD(self):
            parsed = urlsplit(self.path)
            if parsed.path.startswith('/v1/stream/'):
                self.stream(parsed.path, parse_qs(parsed.query), head=True)
            else:
                self.reply(404, {'error': 'not_found'})

        def stream(self, route, query, head):
            match = re.fullmatch(r'/v1/stream/(\d+)/(\d+)', route)
            if not match:
                self.reply(404, {'error': 'not_found'}); return
            try:
                series, episode = int(match.group(1)), int(match.group(2))
                expires = int(query.get('expires', ['0'])[0])
                supplied = query.get('signature', [''])[0]
                if not (int(time.time()) <= expires <= int(time.time()) + TICKET_LIFETIME):
                    self.reply(403, {'error': 'expired_ticket'}); return
                path = video_at(lib, series, episode)
                if path is None or not hmac.compare_digest(supplied, sign(token, series, episode, expires, path)):
                    self.reply(403, {'error': 'invalid_ticket'}); return
                size = path.stat().st_size
                if size <= 0:
                    self.reply(404, {'error': 'empty_file'}); return
                start, end = 0, size - 1
                range_header = self.headers.get('Range', '')
                if range_header:
                    m = re.fullmatch(r'bytes=(\d*)-(\d*)', range_header.strip())
                    if not m or (not m.group(1) and not m.group(2)):
                        self.send_response(416)
                        self.send_header('Content-Range', f'bytes */{size}')
                        self.send_header('Content-Length', '0')
                        self.end_headers(); return
                    if not m.group(1):
                        start = max(0, size - int(m.group(2)))
                    else:
                        start = int(m.group(1))
                        if m.group(2):
                            end = min(end, int(m.group(2)))
                    if start >= size or start > end:
                        self.send_response(416)
                        self.send_header('Content-Range', f'bytes */{size}')
                        self.send_header('Content-Length', '0')
                        self.end_headers(); return
                    end = min(end, start + MAX_RANGE - 1)
                else:
                    end = min(end, MAX_RANGE - 1)
                length = end - start + 1
                self.send_response(206 if range_header or length < size else 200)
                self.send_header('Content-Type', mimetypes.guess_type(str(path))[0] or 'application/octet-stream')
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Content-Length', str(length))
                self.send_header('Content-Range', f'bytes {start}-{end}/{size}') if (range_header or length < size) else None
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.end_headers()
                if head:
                    return
                with path.open('rb') as f:
                    f.seek(start)
                    left = length
                    while left:
                        data = f.read(min(MAX_CHUNK, left))
                        if not data: break
                        self.wfile.write(data)
                        left -= len(data)
            except (OSError, ValueError, TypeError, BrokenPipeError, ConnectionResetError):
                # Client disconnected / file disappeared. Never leak paths.
                pass

        def transcode(self, route, query):
            # Transcodage temps réel : ne fournit jamais le chemin du fichier.
            # L'URL est signée et liée au même ticket que le streaming direct.
            m = re.fullmatch(r'/v1/transcode/(\d+)/(\d+)', route)
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
                ffmpeg = ffmpeg_binary()
                if not ffmpeg:
                    self.reply(503, {'error': 'ffmpeg_unavailable'}); return
                # 480p/720p, débit limité. libx264 en premier, NVENC plus tard.
                height = int(quality)
                bitrate = '1200k' if height == 480 else '2500k'
                maxrate = '1600k' if height == 480 else '3300k'
                args = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin',
                    '-i', str(path), '-map', '0:v:0', '-map', '0:a:0?',
                    '-vf', f'scale=-2:min(ih\,{height})',
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
            pass
    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--library', required=True)
    parser.add_argument('--token', required=True)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    if len(args.token) < 10 or not 1024 <= args.port <= 65535:
        raise SystemExit('Invalid token or port')
    ThreadingHTTPServer(('0.0.0.0', args.port), handler_factory(Path(args.library), args.token)).serve_forever()
