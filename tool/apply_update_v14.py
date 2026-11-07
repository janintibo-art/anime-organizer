#!/usr/bin/env python3
"""V14: transactional/idempotent integration of Windows Python + Android LAN sync."""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
files = ['lib/screens/home_screen.dart','.github/workflows/build.yml','tool/patch_android.py']
original = {name:(ROOT/name).read_text(encoding='utf-8-sig') for name in files}
edited = dict(original)

def one(name, old, new, marker=None):
    s=edited[name]
    if marker and marker in s: return
    if new in s: return
    n=s.count(old)
    if n != 1: raise RuntimeError(f'{name}: expected one unique insertion anchor, found {n}')
    edited[name]=s.replace(old,new,1)

home='lib/screens/home_screen.dart'
one(home,"import 'settings_screen.dart';", "import 'settings_screen.dart';\nimport 'pc_sync_screen.dart';")
one(home, "            actions: [\n", """            actions: [
              IconButton(
                tooltip: Platform.isWindows ? 'Serveur de synchronisation' : 'Se connecter au PC',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PcSyncScreen())),
                icon: const Icon(Icons.sync_alt),
              ),
""",marker="tooltip: Platform.isWindows ? 'Serveur de synchronisation'")
workflow='.github/workflows/build.yml'
one(workflow,"      - name: Compresser l'application\n        shell: pwsh", """      - name: Construire le serveur Python embarqué
        shell: pwsh
        run: |
          python -m pip install --disable-pip-version-check pyinstaller==6.16.0
          python -m PyInstaller --onefile --noconsole --clean --name AnimeOrganizerSyncServer tool/sync_server.py
          Copy-Item dist/AnimeOrganizerSyncServer.exe build/windows/x64/runner/Release/AnimeOrganizerSyncServer.exe -Force
          if (-not (Test-Path build/windows/x64/runner/Release/AnimeOrganizerSyncServer.exe)) { throw 'Serveur Python absent' }

      - name: Compresser l'application
        shell: pwsh""",marker='Construire le serveur Python embarqué')
android='tool/patch_android.py'
one(android, '    with open(MANIFEST, "w", encoding="utf-8") as f:\n        f.write(content)', '''    # Allow local HTTP from the app; access is protected by a pairing code.
    if 'android:usesCleartextTraffic=' not in content:
        content = content.replace('<application',
            '<application android:usesCleartextTraffic="true"', 1)

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)''',marker="if 'android:usesCleartextTraffic=' not in content:")
# Never write partial edits if a later prerequisite is missing.
for name,s in edited.items():
    if s != original[name]:
        (ROOT/name).write_text(s,encoding='utf-8')
        print('Updated:',name)
    else: print('Already updated:',name)
print('V14 code integration complete.')
