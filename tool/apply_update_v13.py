#!/usr/bin/env python3
"""Anime Organizer V13: focused, idempotent source edits."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def patch(path, old, new):
    p = ROOT / path
    s = p.read_text(encoding='utf-8-sig')
    if new in s:
        print('Already updated:', path)
        return
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected 1 anchor; found {count}')
    p.write_text(s.replace(old, new, 1), encoding='utf-8')
    print('Updated:', path)

patch('lib/screens/home_screen.dart',
      "import 'settings_screen.dart';", "import 'settings_screen.dart';\nimport 'pc_sync_screen.dart';")
patch('lib/screens/home_screen.dart',
      '''            actions: [
              IconButton(
                tooltip: 'Verifier les fiches incoherentes',''',
      '''            actions: [
              IconButton(
                tooltip: Platform.isWindows ? 'Serveur de synchronisation' : 'Se connecter au PC',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PcSyncScreen())),
                icon: const Icon(Icons.sync_alt),
              ),
              IconButton(
                tooltip: 'Verifier les fiches incoherentes',''')

patch('.github/workflows/build.yml',
      '''      - name: Compresser l'application
        shell: pwsh''',
      '''      - name: Construire le serveur Python embarqué
        shell: pwsh
        run: |
          python -m pip install --disable-pip-version-check pyinstaller==6.16.0
          python -m PyInstaller --onefile --noconsole --clean --name AnimeOrganizerSyncServer tool/sync_server.py
          Copy-Item dist/AnimeOrganizerSyncServer.exe build/windows/x64/runner/Release/AnimeOrganizerSyncServer.exe -Force
          if (-not (Test-Path build/windows/x64/runner/Release/AnimeOrganizerSyncServer.exe)) { throw 'Serveur Python absent' }

      - name: Compresser l'application
        shell: pwsh''')

patch('tool/patch_android.py',
      '''    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)''',
      '''    # LAN HTTP: permission for private-network communication on Android 9+.
    # No video content is exposed by the server; requests require a pair code.
    if 'android:usesCleartextTraffic=' not in content:
        content = content.replace('<application',
            '<application android:usesCleartextTraffic="true"', 1)

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)''')
print('V13 integration complete.')
