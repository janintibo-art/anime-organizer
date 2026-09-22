import '../models/anime_meta.dart';
import 'ai_service.dart';
import 'anilist_api.dart';
import 'anime_index.dart';
import 'library_controller.dart';
import 'metadata_service.dart';

/// Une proposition retenue : une fiche réelle, et pourquoi elle a été choisie.
class AiPick {
  final AnimeMeta meta;
  final String reason;
  const AiPick(this.meta, this.reason);
}

class AiSearchOutcome {
  final List<AiPick> picks;

  /// Ce que le modèle a compris de la demande, montré tel quel : quand les
  /// résultats déçoivent, c'est le meilleur indice pour reformuler.
  final String understood;
  final String? error;
  final bool usedWeb;
  final int candidates;

  const AiSearchOutcome({
    this.picks = const [],
    this.understood = '',
    this.error,
    this.usedWeb = false,
    this.candidates = 0,
  });
}

/// Traduction d'une demande en filtres AniList.
class _Plan {
  List<String> genres = [];
  List<String> tags = [];
  List<String> formats = [];
  int? yearFrom;
  int? yearTo;
  int? maxEpisodes;
  bool currentSeason = false;
  String sort = 'popular';
  List<String> seeds = [];
  String understood = '';
}

/// Recherche IA en trois temps.
///
/// L'ancienne version demandait directement des titres au modèle, puis les
/// vérifiait : sans accès au web il inventait, ignorait tout ce qui était
/// sorti après son entraînement, et une bonne moitié des propositions
/// disparaissait faute de correspondance.
///
/// Ici le modèle ne fait que ce qu'il fait bien :
///  1. il traduit la demande en filtres (genres, étiquettes, période,
///     nombre d'épisodes, tri) et cite quelques titres qu'il connaît ;
///  2. l'application interroge AniList avec ces filtres et vérifie les
///     titres cités — tout ce qui en sort existe vraiment, et reste à jour
///     puisque le catalogue l'est ;
///  3. le modèle choisit dans cette liste réelle et justifie chaque choix.
///
/// Aucune proposition ne peut être inventée : il choisit par numéro.
class AiSearch {
  /// Deux appels au modèle par recherche : on garde les requêtes courtes
  /// pour ménager les quotas gratuits (Groq compte les jetons par minute
  /// et par jour). Trente titres suffisent largement à bien choisir.
  static const int _maxCandidates = 30;

  static Future<AiSearchOutcome> run({
    required String request,
    int count = 12,
    void Function(String)? onProgress,
  }) async {
    final s = library.settings;
    if (s.aiKey.trim().isEmpty) {
      return const AiSearchOutcome(
          error: 'Renseigne une clé IA dans Réglages → Assistant IA.');
    }

    // --- 1. La demande devient des filtres ---------------------------------
    onProgress?.call('Analyse de la demande…');
    final web = s.aiWebSearch && AiService.supportsWeb(s.aiProvider);
    final plan = await _plan(request, web);
    if (plan == null) {
      return AiSearchOutcome(
          error: AiService.lastError ?? 'Le modèle n\'a pas répondu.');
    }
    final usedWeb = AiService.lastUsedWeb;

    // --- 2. AniList fournit des titres réels -------------------------------
    onProgress?.call('Recherche dans AniList…');
    final pool = <AnimeMeta>[];
    final vus = <String>{};

    void ajouter(Iterable<AnimeMeta> metas) {
      for (final m in metas) {
        final cle = m.sourceId != null
            ? '${m.source}:${m.sourceId}'
            : m.fingerprint;
        if (!vus.add(cle)) continue;
        // Ce que tu possèdes déjà n'est pas une découverte.
        if (library.localMatch(m) != null) continue;
        pool.add(m);
      }
    }

    // Les titres cités par le modèle passent en tête : ce sont souvent les
    // plus fidèles à une demande précise (« comme Steins;Gate »).
    if (plan.seeds.isNotEmpty) {
      onProgress?.call('Vérification de ${plan.seeds.length} titre(s) cité(s)…');
      ajouter(await _verifySeeds(plan.seeds));
    }
    ajouter(await _gather(plan));

    if (pool.isEmpty) {
      return AiSearchOutcome(
        understood: plan.understood,
        usedWeb: usedWeb,
        error: AniListApi.isPaused
            ? 'AniList ne répond plus pour le moment. Réessaie plus tard.'
            : 'Aucun titre trouvé pour ces critères. Essaie une demande '
                'moins restrictive.',
      );
    }

    final candidats = pool.take(_maxCandidates).toList();

    // --- 3. Le modèle choisit dans la liste réelle -------------------------
    onProgress?.call('Sélection parmi ${candidats.length} titres…');
    final picks = await _pick(request, candidats, count);

    return AiSearchOutcome(
      picks: picks,
      understood: plan.understood,
      usedWeb: usedWeb,
      candidates: candidats.length,
    );
  }

  // ------------------------------------------------------------------ plan

  static Future<_Plan?> _plan(String request, bool web) async {
    final s = library.settings;
    final annee = DateTime.now().year;
    final gouts = _gouts();

    const system = 'Tu aides à trouver des séries et films d\'animation '
        'japonaise. Tu ne réponds jamais par une liste de recommandations : '
        'tu traduis la demande en filtres de catalogue, que l\'application '
        'interroge ensuite. Tu réponds uniquement par un objet JSON.';

    final user = StringBuffer()
      ..writeln('Nous sommes en $annee. Demande : « $request »')
      ..writeln()
      ..writeln('Genres disponibles (noms exacts) : '
          '${AniListApi.genreList.join(', ')}')
      ..writeln('Étiquettes disponibles (noms exacts) : '
          '${AniListApi.tagList.join(', ')}');
    if (gouts.isNotEmpty) {
      user
        ..writeln()
        ..writeln(gouts);
    }
    user
      ..writeln()
      ..writeln('Réponds avec ce JSON :')
      ..writeln('{')
      ..writeln('  "understood": "une phrase en français : ce que tu as compris",')
      ..writeln('  "genres": [genres pris dans la liste, 0 à 3],')
      ..writeln('  "tags": [étiquettes prises dans la liste, 0 à 3],')
      ..writeln('  "formats": [parmi TV, TV_SHORT, MOVIE, OVA, ONA ; vide = tous],')
      ..writeln('  "maxEpisodes": nombre ou null,')
      ..writeln('  "currentSeason": true si la demande porte sur la saison en cours,')
      ..writeln('  "yearFrom": année ou null,')
      ..writeln('  "yearTo": année ou null,')
      ..writeln('  "sort": "popular" | "top" | "recent" | "trending",')
      ..writeln('  "seeds": ["Titre romaji exact (année)", ... au plus 8]')
      ..writeln('}')
      ..writeln()
      ..writeln('Règles :')
      ..writeln('- Traduis l\'ambiance en genres : « à pleurer » = Drama, '
          '« léger » = Comedy, « qui fait peur » = Horror.')
      ..writeln('- « Court » : maxEpisodes 13. « Classique » : yearTo vers '
          '2005 et sort « top ». « Nouveautés » ou « récent » : yearFrom '
          '${annee - 1} et sort « recent ». « Cette saison » : currentSeason.')
      ..writeln('- N\'invente aucun critère absent de la demande : dans le doute, '
          'laisse vide ou null. Trop de filtres ne laissent aucun résultat.')
      ..writeln('- seeds : uniquement des titres réels que tu connais avec '
          'certitude, qui correspondent précisément. Liste vide plutôt '
          'qu\'une invention. Ils seront vérifiés.')
      ..writeln('- Ne cite jamais un titre déjà possédé.');
    if (web) {
      user.writeln('- Tu disposes d\'une recherche web : sers-t\'en pour les '
          'sorties récentes, et cite-les dans seeds.');
    }

    final answer = await AiService.ask(
      provider: s.aiProvider,
      apiKey: s.aiKey,
      model: s.aiModel,
      custom: s.aiEndpoint,
      system: system,
      user: user.toString(),
      maxTokens: 600,
      webSearch: web,
      jsonMode: true,
    );
    if (answer == null) return null;

    final map = AiService.extractObject(answer);
    if (map == null) {
      AiService.lastError = 'Réponse illisible du modèle.';
      return null;
    }

    List<String> liste(String cle) => (map[cle] as List? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    int? nombre(String cle, int min, int max) {
      final v = map[cle];
      if (v is! num) return null;
      final n = v.toInt();
      return n < min || n > max ? null : n;
    }

    // Tout ce que le modèle renvoie est confronté aux listes autorisées :
    // un genre mal orthographié ferait échouer toute la requête AniList.
    final plan = _Plan()
      ..understood = (map['understood'] ?? '').toString().trim()
      ..genres = _garder(liste('genres'), AniListApi.genreList).take(3).toList()
      ..tags = _garder(liste('tags'), AniListApi.tagList).take(3).toList()
      ..formats = _garder(
              liste('formats'), const ['TV', 'TV_SHORT', 'MOVIE', 'OVA', 'ONA'])
          .toList()
      ..maxEpisodes = nombre('maxEpisodes', 1, 2000)
      ..currentSeason = map['currentSeason'] == true
      ..yearFrom = nombre('yearFrom', 1950, annee + 1)
      ..yearTo = nombre('yearTo', 1950, annee + 1)
      ..seeds = liste('seeds').take(8).toList()
      ..sort = const {'popular', 'top', 'recent', 'trending'}
              .contains(map['sort']?.toString())
          ? map['sort'].toString()
          : 'popular';

    // Une période à l'envers ne renverrait rien.
    if (plan.yearFrom != null &&
        plan.yearTo != null &&
        plan.yearFrom! > plan.yearTo!) {
      final t = plan.yearFrom;
      plan
        ..yearFrom = plan.yearTo
        ..yearTo = t;
    }
    return plan;
  }

  /// Ne garde que les valeurs présentes dans [autorises], sous leur
  /// orthographe officielle, sans tenir compte de la casse.
  static Iterable<String> _garder(List<String> valeurs, List<String> autorises) {
    final index = {for (final a in autorises) a.toLowerCase(): a};
    return valeurs
        .map((v) => index[v.toLowerCase()])
        .whereType<String>()
        .toSet();
  }

  /// Goûts de la bibliothèque, pour « comme ce que j'ai déjà ».
  static String _gouts() {
    final miens = library.animes.where((a) => a.metaFetched).toList()
      // Les favoris et les séries regardées récemment disent le plus.
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0);
      });
    if (miens.isEmpty) return '';

    final frequence = <String, int>{};
    for (final a in miens) {
      for (final g in a.genres) {
        frequence[g] = (frequence[g] ?? 0) + 1;
      }
    }
    final top = (frequence.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(6)
        .map((e) => e.key);

    final titres = miens.take(20).map((a) => a.romajiTitle ?? a.title);
    return 'Ma bibliothèque (${miens.length} séries), à utiliser seulement si '
        'la demande parle de mes goûts. Genres dominants : ${top.join(', ')}. '
        'Titres déjà possédés : ${titres.join(' ; ')}.';
  }

  // ---------------------------------------------------------------- AniList

  static Future<List<AnimeMeta>> _gather(_Plan plan) async {
    const tris = {
      'popular': 'POPULARITY_DESC',
      'top': 'SCORE_DESC',
      'recent': 'START_DATE_DESC',
      'trending': 'TRENDING_DESC',
    };

    Future<List<AnimeMeta>> essai({bool tags = true, bool tousGenres = true}) =>
        AniListApi.findByCriteria(
          genres: tousGenres ? plan.genres : plan.genres.take(1).toList(),
          tags: tags ? plan.tags : const [],
          formats: plan.formats,
          yearFrom: plan.yearFrom,
          yearTo: plan.yearTo,
          maxEpisodes: plan.maxEpisodes,
          season: plan.currentSeason ? AniListApi.currentSeason() : null,
          seasonYear: plan.currentSeason ? DateTime.now().year : null,
          sort: tris[plan.sort] ?? 'POPULARITY_DESC',
          releasedOnly: plan.sort == 'recent',
        );

    // Des filtres trop serrés ne laissent rien : on élargit par étapes, en
    // gardant jusqu'au bout la période et la durée, qui sont souvent le
    // cœur de la demande (« court », « des années 90 »).
    var out = await essai();
    if (out.length < 8 && plan.tags.isNotEmpty) {
      out = await essai(tags: false);
    }
    if (out.length < 8 && plan.genres.length > 1) {
      out = await essai(tags: false, tousGenres: false);
    }
    return out;
  }

  /// Vérifie les titres cités par le modèle. Un titre n'est retenu que si
  /// le catalogue renvoie une fiche au nom proche et de la bonne année.
  static Future<List<AnimeMeta>> _verifySeeds(List<String> seeds) async {
    final s = library.settings;
    final annee = RegExp(r'\((\d{4})\)\s*$');

    Future<AnimeMeta?> verifier(String seed) async {
      final m = annee.firstMatch(seed);
      final an = m == null ? null : int.tryParse(m.group(1)!);
      final titre = seed.replaceAll(annee, '').trim();
      if (titre.isEmpty) return null;

      // L'index local répond instantanément, sans solliciter AniList.
      if (AnimeIndex.isLoaded) {
        final local = AnimeIndex.match(titre)?.toMeta();
        if (local != null &&
            (an == null || local.year == null || (local.year! - an).abs() <= 1)) {
          return local;
        }
      }

      final trouves = await MetadataService.searchMany(
        titre,
        source: s.metaSource,
        limit: 5,
        tmdbKey: s.tmdbKey,
      );

      AnimeMeta? meilleur;
      var score = 0.0;
      for (final c in trouves) {
        final sim = [
          MetadataService.similarity(titre, c.title),
          if (c.titleRomaji != null)
            MetadataService.similarity(titre, c.titleRomaji!),
        ].reduce((a, b) => a > b ? a : b);
        // Une année franchement différente trahit un homonyme ou un remake.
        if (an != null && c.year != null && (c.year! - an).abs() > 1) continue;
        if (sim > score) {
          score = sim;
          meilleur = c;
        }
      }
      return score >= 0.6 ? meilleur : null;
    }

    // Trois à la fois : les bases gratuites limitent le débit.
    final out = <AnimeMeta>[];
    for (var i = 0; i < seeds.length; i += 3) {
      final lot = seeds.skip(i).take(3).map(verifier);
      out.addAll((await Future.wait(lot)).whereType<AnimeMeta>());
    }
    return out;
  }

  // ---------------------------------------------------------------- choix

  static Future<List<AiPick>> _pick(
      String request, List<AnimeMeta> candidats, int count) async {
    final s = library.settings;

    String ligne(int n, AnimeMeta m) {
      final details = [
        if (m.year != null) '${m.year}',
        if (m.type != null) m.type!,
        if (m.episodes != null) '${m.episodes} ép.',
        if (m.score != null) 'note ${m.score!.toStringAsFixed(1)}',
        if (m.genres.isNotEmpty) m.genres.take(4).join('/'),
      ].join(' · ');
      final resume = (m.synopsis ?? '')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final court =
          resume.length > 120 ? '${resume.substring(0, 120)}…' : resume;
      return '$n. ${m.title} — $details${court.isEmpty ? '' : ' — $court'}';
    }

    final liste = [
      for (var i = 0; i < candidats.length; i++) ligne(i + 1, candidats[i])
    ].join('\n');

    final answer = await AiService.ask(
      provider: s.aiProvider,
      apiKey: s.aiKey,
      model: s.aiModel,
      custom: s.aiEndpoint,
      system: 'Tu choisis, dans une liste de titres réels, ceux qui '
          'répondent le mieux à une demande. Tu ne proposes jamais rien hors '
          'de la liste. Tu réponds uniquement par un objet JSON.',
      user: 'Demande : « $request »\n\nTitres disponibles :\n$liste\n\n'
          'Réponds avec ce JSON :\n'
          '{"picks":[{"n":numéro,"reason":"une phrase en français qui relie '
          'ce titre à la demande"}]}\n'
          'Au plus $count éléments, du plus pertinent au moins pertinent. '
          'Si peu de titres conviennent vraiment, renvoie-en moins : mieux '
          'vaut cinq bons choix que douze approximatifs. La raison doit '
          'parler de la demande, pas résumer l\'histoire.',
      maxTokens: 1000,
      jsonMode: true,
    );

    // Le choix a échoué : on montre quand même les résultats du catalogue,
    // déjà filtrés selon la demande, sans justification.
    List<AiPick> repli() =>
        candidats.take(count).map((m) => AiPick(m, '')).toList();

    if (answer == null) return repli();
    final map = AiService.extractObject(answer);
    final picks = map?['picks'] as List?;
    if (picks == null || picks.isEmpty) return repli();

    final out = <AiPick>[];
    final pris = <int>{};
    for (final p in picks) {
      if (p is! Map) continue;
      final n = p['n'];
      if (n is! num) continue;
      final i = n.toInt() - 1;
      if (i < 0 || i >= candidats.length || !pris.add(i)) continue;
      out.add(AiPick(candidats[i], (p['reason'] ?? '').toString().trim()));
      if (out.length >= count) break;
    }
    return out.isEmpty ? repli() : out;
  }
}
