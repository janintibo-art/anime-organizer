"""Anime Organizer LAN companion, read-only catalogue API, stdlib only."""
import argparse
import hmac
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_CLIENTS = threading.BoundedSemaphore(12)

def clean(s):
    return re.sub(r'[^a-z0-9]', '', str(s).lower())

def snapshot(path):
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    titles = []
    for a in data.get('animes', []):
        episodes = a.get('episodes', [])
        watched = set(a.get('watchedPaths', []))
        viewed = []
        for e in episodes:
            if e.get('bonus') or e.get('path') not in watched:
                continue
            season, number = e.get('season'), e.get('number')
            if isinstance(season, int) and isinstance(number, int):
                viewed.append(f'{season}:{number}')
            elif isinstance(number, int):
                viewed.append(f'1:{number}')
        titles.append({
            'title': a.get('apiTitle') or a.get('folderTitle') or '',
            'folderTitle': a.get('folderTitle') or '',
            'romajiTitle': a.get('romajiTitle') or '',
            'nativeTitle': a.get('nativeTitle') or '',
            'frenchTitle': a.get('frenchTitle') or '',
            'episodeCount': len(episodes),
            'watchedCount': len(watched.intersection(e.get('path') for e in episodes)),
            'watchedKeys': sorted(set(viewed)),
            'favorite': a.get('favorite', False),
            'imageUrl': a.get('imageUrl') or '',
        })
    return {'version': 1, 'libraryName': 'Anime Organizer PC', 'series': titles}

def handler_factory(lib, token):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ('/v1/ping', '/v1/library'):
                self.reply(404, {'error': 'not_found'}); return
            supplied = self.headers.get('X-Anime-Pair-Code', '')
            if not hmac.compare_digest(supplied, token):
                time.sleep(.3)
                self.reply(401, {'error': 'invalid_pairing_code'}); return
            if self.path == '/v1/ping':
                self.reply(200, {'service': 'Anime Organizer', 'version': 1}); return
            try:
                payload = snapshot(lib)
            except (OSError, ValueError, TypeError):
                self.reply(503, {'error': 'library_unavailable'}); return
            self.reply(200, payload)
        def reply(self, status, payload):
            content = json.dumps(payload, ensure_ascii=False).encode('utf-8')
            self.send_response(status)
            self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers(); self.wfile.write(content)
        def log_message(self, fmt, *args):
            pass
    return Handler

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--library', required=True)
    p.add_argument('--token', required=True)
    p.add_argument('--port', type=int, default=8765)
    args = p.parse_args()
    if len(args.token) < 10 or not 1024 <= args.port <= 65535:
        raise SystemExit('Invalid token or port')
    ThreadingHTTPServer(('0.0.0.0', args.port), handler_factory(Path(args.library), args.token)).serve_forever()
