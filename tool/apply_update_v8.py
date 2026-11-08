from pathlib import Path

root=Path(__file__).resolve().parents[1]
def edit(rel,fn):
 p=root/rel
 if not p.exists(): raise RuntimeError('Fichier absent : '+rel)
 original=p.read_text(encoding='utf-8')
 after=fn(original)
 if after!=original:
  p.write_text(after,encoding='utf-8')
  print('Modifié :',rel)
 else: print('Déjà appliqué :',rel)
def replace_once(s,old,new,filename):
 if new in s:return s
 n=s.count(old)
 if n!=1:raise RuntimeError(f'{filename}: attendu 1 emplacement, trouvé {n}')
 return s.replace(old,new,1)

def model(s):
 s=replace_once(s,'  String? backdropUrl;','  String? backdropUrl;\n  bool backdropManual = false;', 'anime.dart')
 s=replace_once(s,'    this.backdropUrl,','    this.backdropUrl,\n    this.backdropManual = false,','anime.dart')
 s=replace_once(s,"        'backdropUrl': backdropUrl,","        'backdropUrl': backdropUrl,\n        'backdropManual': backdropManual,",'anime.dart')
 s=replace_once(s,"        backdropUrl: j['backdropUrl'] as String?,","        backdropUrl: j['backdropUrl'] as String?,\n        backdropManual: j['backdropManual'] as bool? ?? false,",'anime.dart')
 return s

def service(s):
 if 'findBackdrops(' in s:return s
 marker='  static Future<String?> findBackdrop(String title, String apiKey) async {'
 code='''  /// Panoramas de la fiche la plus proche du titre; les autres series sont exclues.
  static Future<List<String>> findBackdrops(String title, String apiKey) async {
    if (title.trim().isEmpty || apiKey.trim().isEmpty) return const [];
    try {
      for (final type in ['tv', 'movie']) {
        final search = Uri.https('api.themoviedb.org', '/3/search/$type', {
          'api_key': apiKey.trim(), 'query': title,
          'language': 'en-US', 'include_adult': 'false',
        });
        final response = await http.get(search).timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        Map<String, dynamic>? match;
        var topScore = 0.0;
        for (final item in (data['results'] as List? ?? const [])) {
          if (item is! Map) continue;
          final candidate = Map<String, dynamic>.from(item);
          final name = (candidate['name'] ?? candidate['title'] ?? '').toString();
          final original = (candidate['original_name'] ?? candidate['original_title'] ?? '').toString();
          final score = _similarity(title, name) > _similarity(title, original)
              ? _similarity(title, name) : _similarity(title, original);
          if (score > topScore) { match = candidate; topScore = score; }
        }
        if (match == null || topScore < 0.78 || match['id'] == null) continue;
        final id = match['id'];
        final imagesUri = Uri.https('api.themoviedb.org', '/3/$type/$id/images', {
          'api_key': apiKey.trim(), 'include_image_language': 'en,null',
        });
        final res = await http.get(imagesUri).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) continue;
        final imageData = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final backdrops = (imageData['backdrops'] as List? ?? const [])
            .whereType<Map>()
            .map((v) => Map<String, dynamic>.from(v))
            .where((v) => (v['width'] as num? ?? 0) >= 800 &&
                           (v['aspect_ratio'] as num? ?? 0) >= 1.5 &&
                           v['file_path'] is String)
            .toList()
          ..sort((a, b) => ((b['vote_average'] as num?) ?? 0)
              .compareTo((a['vote_average'] as num?) ?? 0));
        final paths = <String>{};
        for (final v in backdrops.take(30)) {
          final path = v['file_path'] as String;
          if (path.startsWith('/')) paths.add('https://image.tmdb.org/t/p/w1280$path');
        }
        if (paths.isNotEmpty) return paths.take(18).toList();
      }
    } catch (_) {
      // Reseau ou TMDB indisponible : le fond actuel reste en place.
    }
    return const [];
  }

'''
 return replace_once(s,marker,code+marker,'backdrop_service.dart')

def detail(s):
 s=replace_once(s,'    if (!force && anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;',
  '    if (anime.backdropManual) return;\n    if (!force && anime.backdropUrl != null && anime.backdropUrl!.isNotEmpty) return;', 'detail_screen.dart')
 marker='  Future<void> _run(Future<void> Function() action, String failure) async {'
 code='''  Future<void> _chooseBackdrop() async {
    final key = library.settings.tmdbKey.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renseigne une clé TMDB dans les réglages pour choisir une image.'),
      ));
      return;
    }
    setState(() => _working = true);
    var candidates = <String>[];
    try {
      final titles = <String>{
        if (anime.apiTitle != null) anime.apiTitle!,
        if (anime.romajiTitle != null) anime.romajiTitle!,
        anime.folderTitle,
      };
      for (final title in titles.where((t) => t.trim().isNotEmpty)) {
        candidates = await BackdropService.findBackdrops(title, key);
        if (candidates.isNotEmpty) break;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun panorama disponible pour cette série.'),
      ));
      return;
    }
    // null : annuler; chaine vide : repasser en mode automatique.
    final selection = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Expanded(child: Text('Choisir un panorama',
                style: TextStyle(color: Palette.text, fontSize: 19,
                    fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close)),
          ])),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, ''),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Revenir au panorama automatique'),
            )),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 800 ? 3 : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns, childAspectRatio: 16 / 10,
                crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final url = candidates[i];
                return InkWell(onTap: () => Navigator.pop(ctx, url),
                  child: Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => const Icon(Icons.broken_image))),
                    if (anime.backdropUrl == url)
                      const Align(alignment: Alignment.topRight,
                        child: Padding(padding: EdgeInsets.all(8),
                          child: Icon(Icons.check_circle, color: Colors.white))),
                  ]),
                );
              },
            );
          })),
        ]),
      )),
    );
    if (selection == null || !mounted) return;
    if (selection.isEmpty) {
      anime.backdropManual = false;
      anime.backdropUrl = null;
    } else {
      anime.backdropManual = true;
      anime.backdropUrl = selection;
    }
    await library.save();
    if (mounted) setState(() {});
    if (selection.isEmpty) unawaited(_loadBackdrop());
  }

'''
 s=replace_once(s,marker,code+marker,'detail_screen.dart')
 marker='''                          PopupMenuButton<String>(
                            tooltip: 'Catégorie','''
 code='''                          OutlinedButton.icon(
                            onPressed: _working ? null : _chooseBackdrop,
                            icon: const Icon(Icons.collections_outlined, size: 18),
                            label: const Text('Choisir le panorama'),
                          ),
'''
 s=replace_once(s,marker,code+marker,'detail_screen.dart')
 return s

edit('lib/models/anime.dart',model)
edit('lib/services/backdrop_service.dart',service)
edit('lib/screens/detail_screen.dart',detail)
print('V8 appliquée. Les choix restent stockés dans la bibliothèque locale.')
