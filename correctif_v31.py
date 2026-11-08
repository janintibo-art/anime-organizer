from pathlib import Path

root=Path(__file__).resolve().parent
project=root
if not (project/'lib/screens/player_screen.dart').is_file():
    raise SystemExit('Projet introuvable: execute le correctif depuis ~/anime_organizer')

def replace_once(path,old,new):
    s=path.read_text(encoding='utf-8-sig')
    n=s.count(old)
    if n!=1: raise SystemExit(f'Ancre inattendue ({n}) dans {path}: {old[:60]}')
    path.write_text(s.replace(old,new),encoding='utf-8')

player=project/'lib/screens/player_screen.dart'
s=player.read_text(encoding='utf-8-sig')
start=s.index('  Future<Uint8List?> _captureExactFrame(Episode episode) async {')
end=s.index('\n  void _confirmCapture(',start)
new='''  // V31: extraction a la position du lecteur, avec ffmpeg fourni par le build.
  // Pour un fichier Windows local, ne jamais revenir silencieusement au
  // screenshot Media Kit : il peut provenir d'une autre image en pause.
  Future<Uint8List?> _captureExactFrame(Episode episode) async {
    if (!Platform.isWindows || episode.path.startsWith('http://') ||
        episode.path.startsWith('https://')) return null;
    if (!File(episode.path).existsSync()) {
      throw StateError('Fichier video introuvable : capture annulee.');
    }
    final alongside = File(p.join(p.dirname(Platform.resolvedExecutable), 'ffmpeg.exe'));
    if (!alongside.existsSync()) {
      throw StateError('FFmpeg absent de l\\'installation : capture annulee. Reinstalle la derniere version Windows.');
    }
    // Utiliser la position exposee par le player au moment exact du raccourci,
    // et non le dernier callback du flux (qui peut dater de plusieurs secondes).
    final ms = _player.state.position.inMilliseconds.clamp(0, 2147483647).toInt();
    final time = (ms / 1000.0).toStringAsFixed(3);
    final result = await Process.run(alongside.path, [
      '-hide_banner', '-loglevel', 'error', '-nostdin',
      '-accurate_seek', '-ss', time, '-i', episode.path,
      '-map', '0:v:0', '-frames:v', '1', '-an', '-sn',
      '-f', 'image2pipe', '-vcodec', 'png', 'pipe:1',
    ], stdoutEncoding: null).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0 || result.stdout is! Uint8List ||
        (result.stdout as Uint8List).length < 1024) {
      throw StateError('Extraction a ${time}s impossible (FFmpeg ${result.exitCode}). Aucune mauvaise image enregistree.');
    }
    return result.stdout as Uint8List;
  }
'''
s=s[:start]+new+s[end:]
start=s.index('  void _confirmCapture(Uint8List bytes, String label, {required bool exact}) {')
end=s.index('\n  Future<void> _captureForGallery(',start)
new='''  OverlayEntry? _captureOverlay;
  Timer? _captureOverlayTimer;

  void _clearCaptureOverlay() {
    _captureOverlayTimer?.cancel();
    _captureOverlayTimer = null;
    _captureOverlay?.remove();
    _captureOverlay?.dispose();
    _captureOverlay = null;
  }

  void _confirmCapture(Uint8List bytes, String label, {required bool exact}) {
    if (!mounted) return;
    unawaited(SystemSound.play(SystemSoundType.click));
    _clearCaptureOverlay();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay != null) {
      _captureOverlay = OverlayEntry(builder: (ctx) => Positioned(
        top: MediaQuery.paddingOf(ctx).top + 24, right: 20,
        child: Material(color: Colors.transparent, child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xED10151D),
            border: Border.all(color: const Color(0xFFF3BD69), width: 2),
            borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Image.memory(bytes, width: 115, height: 65, fit: BoxFit.contain),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold))),
          ]),
        )),
      ));
      overlay.insert(_captureOverlay!);
      _captureOverlayTimer = Timer(const Duration(seconds: 5), _clearCaptureOverlay);
    }
    _flash(label);
  }
'''
s=s[:start]+new+s[end:]
s=s.replace('''      final exact = await _captureExactFrame(episode);
      final bytes = exact ?? await _player.screenshot();''','''      final exact = await _captureExactFrame(episode);
      // Sur Windows local FFmpeg est obligatoire. Les captures Media Kit
      // restent disponibles pour Android et les flux distants.
      final bytes = exact ?? await _player.screenshot();''')
s=s.replace('''    HardwareKeyboard.instance.removeHandler(_captureFullscreenKey);
    _autoSave?.cancel();''','''    HardwareKeyboard.instance.removeHandler(_captureFullscreenKey);
    _clearCaptureOverlay();
    _autoSave?.cancel();''')
s=s.replace("label: const Text('Capturer comme panorama principal'),","label: const Text('Capturer comme panorama principal (F3)'),")
# Feedback erreurs visible meme au plein ecran : overlay d'erreur via methode partagee.
s=s.replace("""    } catch (e) {
      if (mounted) _flash('Capture impossible : $e');
    } finally {
      _captureBusy = false;
    }
  }
""","""    } catch (e) {
      if (mounted) {
        _flash('Capture impossible : $e');
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('F2 / F3 : $e'),
        ));
      }
    } finally {
      _captureBusy = false;
    }
  }
""")
player.write_text(s,encoding='utf-8')

workflow=project/'.github/workflows/build.yml'
s=workflow.read_text(encoding='utf-8-sig')
anchor='''      - name: Compresser l'application
        shell: pwsh
        run: Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath AnimeOrganizer-Windows-portable.zip
'''
if s.count(anchor)!=1: raise SystemExit('Ancre workflow introuvable')
addition='''      # V31: ffmpeg est embarque dans la version Windows, pas suppose installe.
      # Le fichier extrait est le vrai executable, pas le shim Chocolatey.
      - name: Embarquer FFmpeg pour les captures F2 F3 exactes
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          choco install ffmpeg -y --no-progress
          if ($LASTEXITCODE -ne 0) { throw 'Installation FFmpeg echouee' }
          $roots = @(
            "$env:ChocolateyInstall\\lib\\ffmpeg",
            'C:\\tools\\ffmpeg',
            'C:\\ProgramData\\chocolatey\\lib\\ffmpeg'
          ) | Where-Object { Test-Path $_ } | Select-Object -Unique
          $candidates = @($roots | ForEach-Object {
            Get-ChildItem -LiteralPath $_ -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue
          } | Where-Object { $_.Length -gt 1000000 } | Sort-Object Length -Descending)
          if ($candidates.Count -eq 0) { throw 'Vrai ffmpeg.exe introuvable apres installation' }
          $dest = 'build/windows/x64/runner/Release/ffmpeg.exe'
          Copy-Item -LiteralPath $candidates[0].FullName -Destination $dest -Force
          & $dest -version
          if ($LASTEXITCODE -ne 0) { throw 'FFmpeg embarque non executable' }
          Get-FileHash -Algorithm SHA256 $dest | Format-List

'''
s=s.replace(anchor,addition+anchor)
workflow.write_text(s,encoding='utf-8')
audit=project/'tool/audit_windows_v29.ps1'
s=audit.read_text(encoding='utf-8-sig')
old='''  "$release/AnimeOrganizerCreditsDetector.exe",
  'AnimeOrganizer-Windows-portable.zip'
'''
new='''  "$release/AnimeOrganizerCreditsDetector.exe",
  "$release/ffmpeg.exe",
  'AnimeOrganizer-Windows-portable.zip'
'''
if s.count(old)!=1:raise SystemExit('Ancre audit introuvable')
audit.write_text(s.replace(old,new),encoding='utf-8')
print('V31 appliquee : lecteur, workflow Windows, audit FFmpeg')
