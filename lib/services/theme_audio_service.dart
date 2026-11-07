import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/anime.dart';

/// Musique locale par fiche, indépendante de la vidéo et du dossier source.
class ThemeAudioService {
  static Future<Directory> folder(Anime anime) async {
    final support = await getApplicationSupportDirectory();
    // Même identifiant stable que les images, sans exposer de chemin source.
    final safe = anime.id.codeUnits.fold<int>(2166136261,
      (hash, n) => ((hash ^ n) * 16777619) & 0xffffffff)
        .toRadixString(16).padLeft(8, '0');
    final folder = Directory(p.join(support.path, 'music', safe));
    await folder.create(recursive: true);
    return folder;
  }

  static Future<String> importAudio(Anime anime, String source) async {
    final input = File(source);
    if (!await input.exists()) throw StateError('Fichier audio introuvable.');
    final extension = p.extension(source).toLowerCase();
    if (!['.mp3', '.flac', '.ogg', '.wav', '.m4a', '.aac', '.opus']
        .contains(extension)) {
      throw StateError('Format audio non pris en charge : $extension');
    }
    final dir = await folder(anime);
    final target = File(p.join(dir.path, 'ambiance$extension'));
    final temporary = File(p.join(dir.path, 'import_tmp$extension'));
    if (await temporary.exists()) await temporary.delete();
    await input.copy(temporary.path);
    if (await target.exists()) await target.delete();
    return (await temporary.rename(target.path)).path;
  }

  static Future<String> extractEpisode(
      Anime anime, Episode episode, Duration from, Duration to) async {
    if (!Platform.isWindows) {
      throw StateError('Extraction disponible sur Windows uniquement.');
    }
    if (from < Duration.zero || to <= from ||
        to - from > const Duration(minutes: 5)) {
      throw StateError('Choisis un extrait de 1 seconde à 5 minutes.');
    }
    if (!await File(episode.path).exists()) {
      throw StateError('Épisode introuvable sur le disque.');
    }
    final ffmpeg = File(p.join(p.dirname(Platform.resolvedExecutable), 'ffmpeg.exe'));
    if (!await ffmpeg.exists()) {
      throw StateError('FFmpeg absent : installe la version Windows V31 ou supérieure.');
    }
    final dir = await folder(anime);
    final temporary = File(p.join(dir.path, 'extrait_tmp.mp3'));
    final output = File(p.join(dir.path, 'ambiance.mp3'));
    if (await temporary.exists()) await temporary.delete();
    String sec(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(3);
    final result = await Process.run(ffmpeg.path, [
      '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
      '-ss', sec(from), '-i', episode.path, '-t', sec(to - from),
      '-map', '0:a:0', '-vn', '-c:a', 'libmp3lame', '-b:a', '192k',
      temporary.path,
    ]).timeout(const Duration(minutes: 2));
    if (result.exitCode != 0 || !await temporary.exists() ||
        await temporary.length() < 1024) {
      if (await temporary.exists()) await temporary.delete();
      throw StateError('Extraction impossible : ${result.stderr.toString().trim()}');
    }
    if (await output.exists()) await output.delete();
    return (await temporary.rename(output.path)).path;
  }
}
