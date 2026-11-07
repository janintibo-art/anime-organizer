import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/anime.dart';

/// Extraits personnels, ranges par anime. Les videos source ne sont jamais modifiees.
class ThemeAudioService {
  static const extensions = <String>{'.mp3', '.flac', '.ogg', '.wav', '.m4a', '.aac', '.opus'};

  static String _safe(String value) {
    const accents = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyy';
    var s = value.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      s = s.replaceAll(accents[i], plain[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.isEmpty) s = 'extrait';
    return s.length > 45 ? s.substring(0, 45) : s;
  }

  static Future<Directory> folder(Anime anime) async {
    final base = await getApplicationSupportDirectory();
    final id = anime.id.codeUnits.fold<int>(2166136261,
      (hash, n) => ((hash ^ n) * 16777619) & 0xffffffff)
        .toRadixString(16).padLeft(8, '0');
    final dir = Directory(p.join(base.path, 'music', id));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<List<String>> listClips(Anime anime) async {
    final dir = await folder(anime);
    final files = await dir.list(followLinks: false)
      .where((item) => item is File && !p.basename(item.path).contains('.partial.') &&
          extensions.contains(p.extension(item.path).toLowerCase()))
      .map((item) => item.path).toList();
    files.sort((a, b) => p.basename(a).compareTo(p.basename(b)));
    return files;
  }

  static Future<void> _verifyInside(Anime anime, String path) async {
    final dir = await folder(anime);
    final root = p.normalize(p.absolute(dir.path));
    final target = p.normalize(p.absolute(path));
    if (!p.isWithin(root, target) || !extensions.contains(p.extension(target).toLowerCase())) {
      throw StateError('Fichier en dehors du dossier audio de cet anime.');
    }
  }

  static Future<File> _available(Directory dir, String base, String ext) async {
    final name = _safe(base);
    for (var i = 1; i <= 9999; i++) {
      final target = File(p.join(dir.path, '${name}_${i.toString().padLeft(3, '0')}$ext'));
      if (!await target.exists()) return target;
    }
    throw StateError('Trop d\'extraits dans ce dossier.');
  }

  static Future<String> importAudio(Anime anime, String source) async {
    final input = File(source);
    if (!await input.exists()) throw StateError('Fichier audio introuvable.');
    final ext = p.extension(source).toLowerCase();
    if (!extensions.contains(ext)) throw StateError('Format audio non pris en charge : $ext');
    final dir = await folder(anime);
    final output = await _available(dir, 'importe_${p.basenameWithoutExtension(source)}', ext);
    final temp = File('${output.path}.partial');
    try {
      await input.copy(temp.path);
      return (await temp.rename(output.path)).path;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  static String _clock(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}m${(d.inSeconds % 60).toString().padLeft(2, '0')}s';

  static Future<String> extractEpisode(Anime anime, Episode episode,
      Duration from, Duration to) async {
    if (!Platform.isWindows) throw StateError('Extraction disponible sur Windows uniquement.');
    if (from < Duration.zero || to <= from || to - from > const Duration(minutes: 5)) {
      throw StateError('Choisis un extrait de 1 seconde a 5 minutes.');
    }
    if (!await File(episode.path).exists()) throw StateError('Episode introuvable sur le disque.');
    final ffmpeg = File(p.join(p.dirname(Platform.resolvedExecutable), 'ffmpeg.exe'));
    if (!await ffmpeg.exists()) throw StateError('FFmpeg absent : reinstalle la derniere version Windows.');
    final dir = await folder(anime);
    final season = (episode.season ?? 1).toString().padLeft(2, '0');
    final number = (episode.number ?? 0).toString().padLeft(2, '0');
    final label = 'dialogue_s${season}e${number}_${_clock(from)}-${_clock(to)}';
    final output = await _available(dir, label, '.mp3');
    final temp = File('${output.path}.partial.mp3');
    String sec(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
    try {
      final result = await Process.run(ffmpeg.path, [
        '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
        '-ss', sec(from), '-i', episode.path, '-t', sec(to - from),
        '-map', '0:a:0', '-vn', '-c:a', 'libmp3lame', '-b:a', '192k', temp.path,
      ]).timeout(const Duration(minutes: 2));
      if (result.exitCode != 0 || !await temp.exists() || await temp.length() < 1024) {
        throw StateError('Extraction impossible : ${result.stderr.toString().trim()}');
      }
      return (await temp.rename(output.path)).path;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  static Future<String> renameClip(Anime anime, String original, String label) async {
    await _verifyInside(anime, original);
    if (!await File(original).exists()) throw StateError('Extrait introuvable.');
    final dir = await folder(anime);
    final target = await _available(dir, label, p.extension(original).toLowerCase());
    return (await File(original).rename(target.path)).path;
  }

  static Future<void> deleteClip(Anime anime, String path) async {
    await _verifyInside(anime, path);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
