import 'dart:convert';

import 'package:http/http.dart' as http;

import 'anilist_api.dart';
import 'jikan_api.dart';

/// Test de connexion : trois appels réels, et le message d'erreur affiché
/// tel quel. Sans permission réseau, on obtient une SocketException ;
/// avec un pare-feu ou un souci d'API, on voit le code HTTP.
class Diagnostics {
  static Future<List<String>> run() async {
    final lines = <String>[];

    lines.add(await _simple(
      'Accès Internet',
      'https://www.google.com/generate_204',
    ));

    lines.add(await _anilist());
    lines.add(await _jikan());

    return lines;
  }

  static Future<String> _simple(String label, String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      return '$label : OK (HTTP ${res.statusCode})';
    } catch (e) {
      return '$label : ÉCHEC — $e';
    }
  }

  static Future<String> _anilist() async {
    try {
      final res = await http
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'query': '{Page(page:1,perPage:1){media(type:ANIME){id title{romaji}}}}'
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        return 'AniList : ÉCHEC — HTTP ${res.statusCode} ${res.body}';
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['errors'] != null) {
        return 'AniList : réponse en erreur — ${body['errors']}';
      }
      final media = ((body['data'] as Map?)?['Page'] as Map?)?['media'] as List?;
      if (media == null || media.isEmpty) {
        return 'AniList : répond mais renvoie une liste vide.';
      }
      final title = ((media.first as Map)['title'] as Map)['romaji'];
      return 'AniList : OK — exemple reçu « $title »';
    } catch (e) {
      return 'AniList : ÉCHEC — $e';
    }
  }

  static Future<String> _jikan() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.jikan.moe/v4/anime?q=naruto&limit=1'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        return 'MyAnimeList : ÉCHEC — HTTP ${res.statusCode}';
      }
      final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as List?;
      if (data == null || data.isEmpty) {
        return 'MyAnimeList : répond mais renvoie une liste vide.';
      }
      return 'MyAnimeList : OK';
    } catch (e) {
      return 'MyAnimeList : ÉCHEC — $e';
    }
  }

  /// Dernières erreurs mémorisées par les services pendant l'usage normal.
  static List<String> lastErrors() {
    final out = <String>[];
    if (AniListApi.lastError != null) {
      out.add('Dernière erreur AniList : ${AniListApi.lastError}');
    }
    if (JikanApi.lastError != null) {
      out.add('Dernière erreur MyAnimeList : ${JikanApi.lastError}');
    }
    return out;
  }
}
