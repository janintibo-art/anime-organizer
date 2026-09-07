import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/anime.dart';

/// Parcourt les dossiers choisis par l'utilisateur et regroupe les fichiers
/// video en series.
class Scanner {
  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.webm', '.m4v',
    '.flv', '.ts', '.wmv', '.mpg', '.mpeg', '.ogv', '.3gp', '.m2ts',
  };

  static final RegExp _brackets = RegExp(r'\[[^\]]*\]|\([^)]*\)|\{[^}]*\}');
  static final RegExp _tags = RegExp(
    r'\b(vostfr|vosta|vf|vo|multi|hardsub|softsub|subfrench|french|truefrench|'
    r'web-?dl|webrip|bluray|blu-ray|bdrip|brrip|hdrip|dvdrip|hdtv|remux|'
    r'x264|x265|h ?264|h ?265|hevc|avc|aac|ac3|eac3|flac|opus|dts|'
    r'10 ?bits?|8 ?bits?|1080p|720p|480p|360p|2160p|4k|uhd|'
    r'uncensored|censored|repack|proper|final|complete|integrale|vostfr)\b',
    caseSensitive: false,
  );
  static final RegExp _episodeMarks = RegExp(
    r'\b(s\d{1,2} ?e\d{1,3}|saison ?\d{1,2}|season ?\d{1,2}|'
    r'episode ?\d{1,3}|ep ?\d{1,3}|vol ?\d{1,3})\b',
    caseSensitive: false,
  );
  static final RegExp _trailingNumber = RegExp(r'[\s\-–—]+\d{1,3}\s*$');
  static final RegExp _spaces = RegExp(r'\s{2,}');
  static final RegExp _edges = RegExp(r'^[\s\-–—_]+|[\s\-–—_]+$');
  static final RegExp _digits = RegExp(r'\d+');

  /// Transforme `[HorribleSubs] Made.in.Abyss - 03 [1080p].mkv`
  /// en `Made in Abyss`.
  static String cleanTitle(String raw) {
    var s = raw;
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(RegExp(r'[._]+'), ' ');
    s = s.replaceAll(_tags, ' ');
    s = s.replaceAll(_episodeMarks, ' ');
    s = s.replaceAll(_trailingNumber, ' ');
    s = s.replaceAll(_spaces, ' ');
    s = s.replaceAll(_edges, '');
    s = s.trim();
    return s.isEmpty ? raw.trim() : s;
  }

  /// Tri naturel : « Episode 2 » avant « Episode 10 ».
  static int naturalCompare(String a, String b) {
    final ma = _digits.allMatches(a).toList();
    final mb = _digits.allMatches(b).toList();
    if (ma.isNotEmpty && mb.isNotEmpty) {
      final pa = a.substring(0, ma.last.start).toLowerCase();
      final pb = b.substring(0, mb.last.start).toLowerCase();
      if (pa == pb) {
        final na = int.tryParse(ma.last.group(0)!) ?? 0;
        final nb = int.tryParse(mb.last.group(0)!) ?? 0;
        if (na != nb) return na.compareTo(nb);
      }
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Dossier de serie : premier niveau sous la racine scannee.
  static String _seriesFolder(String root, String filePath) {
    final rel = p.relative(p.dirname(filePath), from: root);
    if (rel == '.' || rel.isEmpty) return root;
    final first = p.split(rel).first;
    return p.join(root, first);
  }

  static Future<List<Anime>> scanFolders(
    List<String> roots, {
    void Function(String message)? onProgress,
  }) async {
    final Map<String, List<File>> groups = {};
    final Map<String, String> titles = {};

    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      onProgress?.call('Lecture de ${p.basename(root)}');

      final stream = dir.list(recursive: true, followLinks: false).handleError(
            (Object _) {},
            test: (Object e) => e is FileSystemException,
          );

      await for (final entity in stream) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (!videoExtensions.contains(ext)) continue;

        final parent = p.dirname(entity.path);
        String key;
        String title;
        if (p.equals(parent, root)) {
          // Fichier isole a la racine : une entree par fichier.
          title = cleanTitle(p.basenameWithoutExtension(entity.path));
          key = p.join(root, '::$title');
        } else {
          key = _seriesFolder(root, entity.path);
          title = cleanTitle(p.basename(key));
        }
        groups.putIfAbsent(key, () => <File>[]).add(entity);
        titles[key] = title;
      }
    }

    final result = <Anime>[];
    groups.forEach((key, files) {
      files.sort((a, b) => naturalCompare(p.basename(a.path), p.basename(b.path)));
      result.add(
        Anime(
          id: key,
          folderTitle: titles[key] ?? p.basename(key),
          episodes: files
              .map((f) => Episode(
                    path: f.path,
                    name: p.basenameWithoutExtension(f.path),
                  ))
              .toList(),
        ),
      );
    });

    result.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return result;
  }
}
