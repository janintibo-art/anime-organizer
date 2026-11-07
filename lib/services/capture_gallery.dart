import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/anime.dart';

/// Galerie personnelle. Ne touche jamais au fichier video source.
class CaptureGallery {
  static String _safe(String value) {
    const accents = 'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ';
    const plain = 'aaaaaaceeeeiiiinooooouuuuyy';
    var text = value.toLowerCase();
    for (var i = 0; i < accents.length; i++) {
      text = text.replaceAll(accents[i], plain[i]);
    }
    text = text.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    text = text.replaceAll(RegExp(r'^_+|_+$'), '');
    if (text.isEmpty) return 'anime';
    return text.length > 48 ? text.substring(0, 48) : text;
  }

  static String _stableId(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<Directory> folder(Anime anime) async {
    final base = await getApplicationSupportDirectory();
    final path = p.join(base.path, 'images',
        '${_safe(anime.folderTitle)}_${_stableId(anime.id)}');
    final dir = Directory(path);
    await dir.create(recursive: true);
    return dir;
  }

  static Future<List<String>> list(Anime anime) async {
    final dir = await folder(anime);
    final files = await dir.list(followLinks: false)
        .where((entity) => entity is File &&
            ['.png', '.jpg', '.jpeg', '.webp']
                .contains(p.extension(entity.path).toLowerCase()))
        .map((entity) => entity.path).toList();
    files.sort();
    return files;
  }

  static Future<String> save(Anime anime, Episode episode, Uint8List png) async {
    if (png.length < 1024) throw const FormatException('Capture vide.');
    final dir = await folder(anime);
    final slug = _safe(anime.folderTitle);
    final season = (episode.season ?? 1).toString().padLeft(2, '0');
    final ep = episode.number?.toString().padLeft(2, '0') ?? 'xx';
    final prefix = '${slug}_s${season}e${ep}_';
    final known = await list(anime);
    var number = 1;
    final occupied = known.map(p.basename).toSet();
    while (occupied.contains('$prefix${number.toString().padLeft(3, '0')}.png')) {
      number++;
    }
    final file = File(p.join(dir.path, '$prefix${number.toString().padLeft(3, '0')}.png'));
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }
}
