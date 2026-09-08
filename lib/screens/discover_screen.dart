import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/anime_meta.dart';
import '../models/labels.dart';
import '../services/anilist_api.dart';
import '../services/jikan_api.dart';
import '../services/animethemes_api.dart';
import '../services/kitsu_api.dart';
import '../services/tmdb_api.dart';
import '../services/library_controller.dart';
import '../services/metadata_service.dart';
import 'discover_detail_screen.dart';

/// Onglet Découvrir : le catalogue AniList, filtrable, avec chargement au fil
/// du défilement. Ce que tu as déjà sur le disque est signalé d'un repère.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const Map<String, String> _sorts = {
    'TRENDING_DESC': 'Tendances',
    'POPULARITY_DESC': 'Populaires',
    'SCORE_DESC': 'Mieux notés',
    'START_DATE_DESC': 'Nouveautés',
    'FAVOURITES_DESC': 'Favoris du site',
  };

  static const Map<String, String> _formats = {
    '': 'Tout',
    'TV': 'Séries',
    'MOVIE': 'Films',
    'OVA': 'OAV',
    'ONA': 'ONA',
  };

  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  String _sort = 'TRENDING_DESC';
  String _format = '';
  String _genre = '';
  String _search = '';
  bool _seasonOnly = false;
  bool _wishlistOnly = false;

  final List<AnimeMeta> _items = [];
  final Set<int> _seen = {};
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 1;
      _hasNext = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext || _wishlistOnly) return;
    setState(() => _loading = true);

    // Une recherche passe aussi par les secours si AniList est coupe.
    final result = await AniListApi.browse(
      page: _page,
      perPage: 30,
      sort: _sort,
      genre: _genre.isEmpty ? null : _genre,
      format: _format.isEmpty ? null : _format,
      season: _seasonOnly ? AniListApi.currentSeason() : null,
      seasonYear: _seasonOnly ? DateTime.now().year : null,
      search: _search.length >= 2 ? _search : null,
    );

    // Une recherche doit aussi profiter des sources de secours.
    if (_search.length >= 2 && result.items.isEmpty) {
      final fallback = await MetadataService.searchMany(
        _search,
        source: 'auto',
        limit: 20,
        tmdbKey: library.settings.tmdbKey,
      );
      if (fallback.isNotEmpty && mounted) {
        setState(() {
          for (final item in fallback) {
            final id = item.sourceId;
            if (id != null && _seen.contains(id)) continue;
            if (id != null) _seen.add(id);
            _items.add(item);
          }
          _hasNext = false;
          _loading = false;
          _notice = 'Résultats fournis par les sources de secours.';
        });
        return;
      }
    }

    // AniList muet : on bascule sur MyAnimeList plutot que d'afficher un vide.
    var items = result.items;
    var hasNext = result.hasNext;
    String? notice;
    if (items.isEmpty) {
      final backup = await JikanApi.browse(
        page: _page,
        sort: _sort,
        genre: _genre.isEmpty ? null : _genre,
        format: _format.isEmpty ? null : _format,
      );
      if (backup.isNotEmpty) {
        items = backup;
        hasNext = backup.length >= 20;
        notice = 'AniList ne répond pas, liste fournie par MyAnimeList.';
      } else {
        final third = await KitsuApi.browse(
          page: _page,
          perPage: 20,
          sort: _sort,
          genre: _genre.isEmpty ? null : _genre,
          format: _format.isEmpty ? null : _format,
        );
        if (third.isNotEmpty) {
          items = third;
          hasNext = third.length >= 20;
          notice = 'AniList et MyAnimeList indisponibles, liste fournie par Kitsu.';
        } else {
          final fourth = await AnimeThemesApi.browse(
            page: _page,
            sort: _sort,
            format: _format.isEmpty ? null : _format,
          );
          if (fourth.isNotEmpty) {
            items = fourth;
            hasNext = fourth.length >= 15;
            notice = 'Liste fournie par AnimeThemes.';
          } else if (library.settings.tmdbKey.trim().isNotEmpty) {
            final fifth =
                await TmdbApi.browse(library.settings.tmdbKey, page: _page, sort: _sort);
            if (fifth.isNotEmpty) {
              items = fifth;
              hasNext = fifth.length >= 15;
              notice = 'Liste fournie par TMDB, en français.';
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _notice = notice;
      for (final item in items) {
        final id = item.sourceId;
        if (id != null && _seen.contains(id)) continue;
        if (id != null) _seen.add(id);
        _items.add(item);
      }
      _hasNext = hasNext;
      _page++;
      _loading = false;
      if (_items.isEmpty && !hasNext) {
        final details = [
          if (AniListApi.lastError != null) 'AniList : ${AniListApi.lastError}',
          if (JikanApi.lastError != null)
            'MyAnimeList : ${JikanApi.lastError}',
          if (KitsuApi.lastError != null) 'Kitsu : ${KitsuApi.lastError}',
          if (AnimeThemesApi.lastError != null)
            'AnimeThemes : ${AnimeThemesApi.lastError}',
          if (TmdbApi.lastError != null) 'TMDB : ${TmdbApi.lastError}',
        ].join('\n\n');

        _error = details.isEmpty
            ? 'Aucun résultat. Change de filtre ou réessaie plus tard.'
            : 'Les trois catalogues sont muets.\n\n$details\n\n'
                'Lance « Tester la connexion » dans les réglages.';
      }
    });
  }

  void _open(AnimeMeta meta) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DiscoverDetailScreen(meta: meta)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final items = _wishlistOnly ? library.wishlist : _items;

        return Scaffold(
          appBar: darkAppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(width: 3, height: 18, color: Palette.shu),
                    const SizedBox(width: 8),
                    const Text('Découvrir'),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 11, top: 1),
                  child: Text(
                    'AniList · MyAnimeList · Kitsu',
                    style: TextStyle(
                        color: Palette.muted,
                        fontSize: 10.5,
                        letterSpacing: 0.8),
                  ),
                ),
              ],
            ),
          ),
          body: Column(
            children: [
              _filters(),
              if (_notice != null && !_wishlistOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(_notice!,
                      style: const TextStyle(
                          color: Palette.kin, fontSize: 11.5)),
                ),
              if (_loading && _items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Palette.raised,
                      color: Palette.shu),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _wishlistOnly
                                ? 'Ta liste « à voir » est vide. Ajoute des séries depuis le catalogue.'
                                : (_error ?? 'Chargement du catalogue…'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Palette.muted),
                          ),
                        ),
                      )
                    : _grid(items),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grid(List<AnimeMeta> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 8);
        return GridView.builder(
          controller: _wishlistOnly ? null : _scroll,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: 0.52,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: items.length + (_loading && !_wishlistOnly ? columns : 0),
          itemBuilder: (context, i) {
            if (i >= items.length) {
              return Container(
                decoration: BoxDecoration(
                  color: Palette.surface,
                  borderRadius: BorderRadius.circular(radiusMd),
                ),
              );
            }
            return _tile(items[i]);
          },
        );
      },
    );
  }

  Widget _tile(AnimeMeta meta) {
    final local = library.localMatch(meta);
    final wished = library.inWishlist(meta);

    return GestureDetector(
      onTap: () => _open(meta),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radiusMd),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (meta.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: meta.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: Palette.raised),
                      errorWidget: (_, __, ___) =>
                          Container(color: Palette.raised),
                    )
                  else
                    Container(color: Palette.raised),
                  if (meta.score != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Palette.shu,
                          borderRadius: BorderRadius.circular(radiusSm),
                        ),
                        child: Text(
                          meta.score!.toStringAsFixed(1),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (local != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: const Color(0xE6D6B86A),
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        child: const Text(
                          'Dans ta bibliothèque',
                          style: TextStyle(
                              color: Palette.ink,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  if (wished && local == null)
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(Icons.bookmark,
                          color: Palette.sakura, size: 20),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            meta.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (meta.year != null) '${meta.year}',
              if (meta.genres.isNotEmpty) Labels.genre(meta.genres.first),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Palette.kin),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- filtres

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              setState(() {
                _search = v.trim();
                _wishlistOnly = false;
              });
              _reload();
            },
            decoration: fieldDecoration(
              hintText: 'Chercher dans le catalogue',
              prefixIcon:
                  const Icon(Icons.search, color: Palette.muted, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          color: Palette.muted, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                        _reload();
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _menu<String>(
                  label: _wishlistOnly
                      ? 'Ma liste'
                      : (_sorts[_sort] ?? 'Tendances'),
                  items: _sorts,
                  onSelected: (v) {
                    setState(() {
                      _sort = v;
                      _wishlistOnly = false;
                    });
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _menu<String>(
                  label: _formats[_format] ?? 'Tout',
                  items: _formats,
                  onSelected: (v) {
                    setState(() => _format = v);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Saison en cours',
                  selected: _seasonOnly,
                  onTap: () {
                    setState(() => _seasonOnly = !_seasonOnly);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Ma liste (${library.wishlist.length})',
                  selected: _wishlistOnly,
                  onTap: () => setState(() => _wishlistOnly = !_wishlistOnly),
                ),
                const SizedBox(width: 8),
                _chip(
                  label: 'Tous genres',
                  selected: _genre.isEmpty,
                  onTap: () {
                    setState(() => _genre = '');
                    _reload();
                  },
                ),
                for (final g in AniListApi.genreList) ...[
                  const SizedBox(width: 8),
                  _chip(
                    label: g,
                    selected: _genre == g,
                    onTap: () {
                      setState(() => _genre = _genre == g ? '' : g);
                      _reload();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu<T>({
    required String label,
    required Map<String, String> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      color: Palette.surface,
      onSelected: onSelected,
      itemBuilder: (_) => items.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Palette.raised,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: Palette.text,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Palette.shu : Colors.transparent,
          border: Border.all(color: selected ? Palette.shu : Palette.line),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : Palette.muted,
          ),
        ),
      ),
    );
  }
}
