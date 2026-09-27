import 'package:flutter/material.dart';

import '../models/labels.dart';
import '../services/anilist_api.dart';
import 'discover_screen.dart';

/// Ouvre le catalogue AniList filtré sur un genre, depuis une fiche.
///
/// Le nom reçu peut être brut (« Comedy ») ou déjà traduit (« Comédie ») :
/// les fiches de la bibliothèque enregistrent la version française.
/// AniList a dix-huit genres figés et des centaines d'étiquettes.
class GenreLinks {
  static void open(BuildContext context, String name) {
    final candidates = <String>[...Labels.englishNames(name), name];

    String? genre;
    for (final c in candidates) {
      genre = _match(AniListApi.genreList, c);
      if (genre != null) break;
    }

    String? tag;
    if (genre == null) {
      for (final c in candidates) {
        tag = _match(AniListApi.tagList, c);
        if (tag != null) break;
      }
      // Absente du menu : on la tente quand même comme étiquette AniList,
      // qui en connaît bien plus que le menu n'en montre. Sans résultat,
      // l'écran le dit au lieu d'afficher une liste sans rapport.
      tag ??= _titleCase(candidates.first);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiscoverScreen(initialGenre: genre, initialTag: tag),
      ),
    );
  }

  static String? _match(List<String> list, String name) {
    final wanted = name.trim().toLowerCase();
    for (final item in list) {
      if (item.toLowerCase() == wanted) return item;
    }
    return null;
  }

  /// « coming of age » → « Coming of Age », l'écriture d'AniList.
  static String _titleCase(String value) {
    const small = {'of', 'and', 'the', 'for', 'in', 'a', 'to'};
    final words = value.trim().split(RegExp(r'\s+'));
    return [
      for (var i = 0; i < words.length; i++)
        if (words[i].isEmpty)
          words[i]
        else if (i > 0 && small.contains(words[i].toLowerCase()))
          words[i].toLowerCase()
        else
          words[i][0].toUpperCase() + words[i].substring(1),
    ].join(' ');
  }
}
