from pathlib import Path
p = Path('lib/screens/player_screen.dart')
s = p.read_text(encoding='utf-8')
marker = '// V30_EXACT_CAPTURE_FEEDBACK'
if marker in s:
    print('V30 deja appliquee')
    raise SystemExit(0)
need = ["import 'dart:io';", "  // V26_F2_CAPTURE:", "  void _persist({bool forceWatched = false}) {", "label: const Text('Capturer comme panorama principal')", "  void _flash(String message) {", "if (key == LogicalKeyboardKey.f2)"]
for x in need:
    if x not in s: raise SystemExit('Structure inattendue, aucun fichier modifie: ' + x)
start=s.index('  // V26_F2_CAPTURE:')
end=s.index('  void _persist({bool forceWatched = false}) {', start)
block=r'''  // V30_EXACT_CAPTURE_FEEDBACK: on prefere la trame a la position affichee.
  // Certains pilotes Media Kit rendent une ancienne image avec screenshot()
  // lorsque la video est en pause / plein ecran.
  bool _captureBusy = false;

  Future<Uint8List?> _captureExactFrame(Episode episode) async {
    if (!Platform.isWindows || episode.path.startsWith('http://') ||
        episode.path.startsWith('https://') || !File(episode.path).existsSync()) {
      return null;
    }
    // FFmpeg facultatif dans le PATH ou a cote de l'application.
    final alongside = File(p.join(Platform.resolvedExecutable == ''
        ? '' : p.dirname(Platform.resolvedExecutable), 'ffmpeg.exe'));
    final executable = alongside.existsSync() ? alongside.path : 'ffmpeg';
    final position = _position.inMilliseconds.clamp(0, 2147483647).toInt();
    final time = (position / 1000.0).toStringAsFixed(3);
    try {
      // -ss apres -i : seek precis, non keyframe seulement.
      final result = await Process.run(executable, [
        '-hide_banner', '-loglevel', 'error', '-nostdin',
        '-i', episode.path, '-ss', time,
        '-map', '0:v:0', '-frames:v', '1', '-an', '-sn',
        '-f', 'image2pipe', '-vcodec', 'png', 'pipe:1',
      ], stdoutEncoding: null).timeout(const Duration(seconds: 25));
      if (result.exitCode == 0 && result.stdout is Uint8List) {
        final data = result.stdout as Uint8List;
        if (data.length > 1024) return data;
      }
    } catch (_) {
      // Absence de FFmpeg : Media Kit reste disponible en secours.
    }
    return null;
  }

  void _confirmCapture(Uint8List bytes, String label, {required bool exact}) {
    if (!mounted) return;
    unawaited(SystemSound.play(SystemSoundType.click));
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      content: Row(children: [
        Image.memory(bytes, width: 104, height: 59, fit: BoxFit.cover),
        const SizedBox(width: 12),
        Expanded(child: Text(exact ? label :
            '$label\nCapture Media Kit : verifie l\'apercu si la video etait en pause.')),
      ]),
    ));
    _flash(label);
  }

  Future<void> _captureForGallery({bool useAsPanorama = false}) async {
    final anime = widget.anime;
    if (anime == null || widget.episodes.isEmpty || _captureBusy) return;
    _captureBusy = true;
    try {
      final episode = widget.episodes[_index.clamp(0, widget.episodes.length - 1)];
      final exact = await _captureExactFrame(episode);
      final bytes = exact ?? await _player.screenshot();
      if (bytes == null || bytes.length < 1024) {
        if (mounted) _flash('Capture impossible pour cette video.');
        return;
      }
      final path = await CaptureGallery.save(anime, episode, bytes);
      if (useAsPanorama) {
        anime.backdropLocalPath = path;
        anime.backdropManual = true;
        anime.backdropAlignX = 0;
        anime.backdropAlignY = 0;
        await library.save();
      }
      library.refresh();
      _confirmCapture(bytes, useAsPanorama
          ? 'F3 : panorama principal enregistre.'
          : 'F2 : capture enregistree.', exact: exact != null);
    } catch (e) {
      if (mounted) _flash('Capture impossible : $e');
    } finally {
      _captureBusy = false;
    }
  }

'''
s=s[:start]+block+s[end:]
s=s.replace("import 'dart:io';", "import 'dart:io';\nimport 'dart:typed_data';", 1)
s=s.replace("label: const Text('Capturer comme panorama principal')", "label: const Text('Capturer comme panorama principal (F3)')", 1)
p.write_text(s, encoding='utf-8')
print('V30: player_screen.dart modifie')
