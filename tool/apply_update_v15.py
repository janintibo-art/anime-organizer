#!/usr/bin/env python3
"""Apply V15 carefully to the already installed V14 project."""
from pathlib import Path


def edit(path, old, new):
    target = Path(path)
    if not target.is_file():
        raise RuntimeError(f'File missing: {path}')
    data = target.read_text(encoding='utf-8')
    if new in data:
        print('Already updated:', path)
        return
    count = data.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected exactly one anchor, found {count}: {old[:80]!r}')
    target.write_text(data.replace(old, new, 1), encoding='utf-8')
    print('Updated:', path)


sync = 'lib/screens/pc_sync_screen.dart'
edit(sync,
     "import '../services/library_controller.dart';",
     "import '../services/library_controller.dart';\nimport 'remote_episodes_screen.dart';")
edit(sync,
     "            ..._remote.take(300).map((a) => ListTile(\n              title: Text('${a['title'] ?? ''}'),\n              subtitle: Text('${a['episodeCount'] ?? 0} épisodes · ${a['watchedCount'] ?? 0} vus sur le PC'),\n            )),",
     "            ..._remote.take(300).map((a) => ListTile(\n              title: Text('${a['title'] ?? ''}'),\n              subtitle: Text('${a['episodeCount'] ?? 0} épisodes · ${a['watchedCount'] ?? 0} vus sur le PC'),\n              trailing: const Icon(Icons.play_circle_outline),\n              onTap: a['id'] is int ? () => Navigator.of(context).push(\n                MaterialPageRoute(builder: (_) => RemoteEpisodesScreen(\n                  host: _address.text.trim(),\n                  pairCode: _code.text.trim().toUpperCase(),\n                  seriesId: a['id'] as int,\n                  seriesTitle: '${a['title'] ?? ''}',\n                ))) : null,\n            )),")
edit(sync,
     "'Le PC et le téléphone doivent être sur le même réseau local. Les vidéos restent sur le PC.',",
     "'Connecte les deux appareils au même Wi-Fi ou à ton réseau privé Tailscale. Les vidéos restent sur le PC.',")

player = 'lib/screens/player_screen.dart'
edit(player,
     'widget.episodes.map((e) => Media(Uri.file(e.path).toString())).toList(),',
     "widget.episodes.map((e) => Media(e.path.startsWith('http://') || e.path.startsWith('https://')\n          ? e.path : Uri.file(e.path).toString())).toList(),")

# Android MediaKit/HTTP connections on a private LAN must be explicitly allowed.
patch = Path('tool/patch_android.py')
s = patch.read_text(encoding='utf-8')
needle = '    if "requestLegacyExternalStorage" not in content:'
insert = '''    # HTTP playback is confined to the user's trusted LAN or encrypted tailnet.
    # Do not expose the embedded server to a public port.
    if 'android:usesCleartextTraffic=' not in content:
        content = re.sub(r'<application',
                         '<application\\n        android:usesCleartextTraffic="true"',
                         content, count=1)

'''
if insert not in s:
    if s.count(needle) != 1:
        raise RuntimeError('Android manifest patch anchor absent')
    patch.write_text(s.replace(needle, insert + needle, 1), encoding='utf-8')
    print('Updated: tool/patch_android.py')

print('V15 patch applied. Run git diff --check and push.')
