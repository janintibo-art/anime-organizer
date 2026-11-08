from pathlib import Path
import re

root=Path.home()/'anime_organizer'
file=root/'lib/screens/detail_screen.dart'
if not file.exists():
    raise SystemExit('Projet absent : '+str(file))
s=file.read_text(encoding='utf-8')
if '// V20_IMMERSIVE' in s:
    print('V20 déjà appliquée : aucune modification supplémentaire')
    raise SystemExit(0)
assert 'Widget _banner() {' in s and 'Widget _resumeButton() {' in s, 'Structure de bandeau inattendue'
assert 'Widget _titleVariants() {' in s and 'void _play(int index' in s, 'Structure de titres inattendue'
assert '                      _resumeButton(),' in s, 'Zone de lecture introuvable'

# Barre du haut réduite à la navigation, sans photo redondante.
a=s.index('  Widget _banner() {')
b=s.index('  Widget _resumeButton() {', a)
s=s[:a]+'''  // V20_IMMERSIVE : le panorama unique est celui du fond de la fiche.
  Widget _banner() {
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 54,
      backgroundColor: Palette.ink.withOpacity(0.66),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.white,
      title: Text(anime.title, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      actions: [
        IconButton(
          tooltip: 'Favori',
          onPressed: () => library.toggleFavorite(anime),
          icon: Icon(anime.favorite ? Icons.favorite : Icons.favorite_border,
              color: anime.favorite ? Palette.sakura : Colors.white),
        ),
      ],
    );
  }

  Widget _identityHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radiusMd),
            child: SizedBox(width: 82, height: 116,
                child: PosterImage(anime: anime, iconSize: 24)),
          ),
          const SizedBox(width: 15),
          Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(anime.title, maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 25,
                    height: 1.12, fontWeight: FontWeight.w700)),
              if (anime.nativeTitle != null &&
                  anime.nativeTitle!.trim().isNotEmpty &&
                  anime.nativeTitle != anime.title) ...[
                const SizedBox(height: 5),
                Text(anime.nativeTitle!, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Palette.muted, fontSize: 12)),
              ],
              if (anime.progress > 0) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(value: anime.progress, minHeight: 3,
                  backgroundColor: const Color(0x55FFFFFF), color: Palette.kin),
                const SizedBox(height: 4),
                Text('${anime.watchedCount} / ${anime.episodes.length} épisodes vus',
                    style: TextStyle(color: Palette.muted, fontSize: 11)),
              ],
            ],
          )),
        ],
      ),
    );
  }

'''+s[b:]
# Bouton compact, sombre, centré sur le contexte, pas barre rouge.
a=s.index('  Widget _resumeButton() {')
b=s.index('  Widget _badges() {',a)
s=s[:a]+'''  Widget _resumeButton() {
    if (anime.episodes.isEmpty) return const SizedBox.shrink();
    final index = anime.resumeIndex;
    final at = anime.resumePosition;
    final label = anime.finished
        ? 'Revoir depuis le début'
        : (at > Duration.zero
            ? "Reprendre l'épisode ${index + 1}"
            : "Lire l'épisode ${index + 1}");
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => anime.finished ? _play(0) : _play(index, at: at),
        icon: Icon(Icons.play_arrow_rounded, color: Palette.kin, size: 22),
        label: Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xB51A1C24),
          side: const BorderSide(color: Color(0xAAE5AF6D)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
    );
  }

'''+s[b:]
# transformer les titres en panneau déroulant qui n'obstrue plus l'arrière-plan.
a=s.index('  Widget _titleVariants() {')
b=s.index('  void _play(int index',a)
s=s[:a]+'''  Widget _titleVariants() {
    final rows = <List<String>>[
      if (anime.romajiTitle != null && anime.romajiTitle!.isNotEmpty)
        ['Romaji', anime.romajiTitle!],
      if (anime.apiTitle != null && anime.apiTitle!.isNotEmpty)
        ['Anglais', anime.apiTitle!],
      if (anime.frenchTitle != null && anime.frenchTitle!.isNotEmpty)
        ['Français', anime.frenchTitle!],
      if (anime.nativeTitle != null && anime.nativeTitle!.isNotEmpty)
        ['日本語', anime.nativeTitle!],
    ];
    if (rows.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 3),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          collapsedBackgroundColor: Colors.transparent,
          backgroundColor: const Color(0x6611151C),
          iconColor: Palette.kin,
          collapsedIconColor: Palette.kin,
          title: Text('Titres et langues', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Palette.kin)),
          children: [for (final row in rows)
            Padding(padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 72, child: Text(row[0],
                      style: TextStyle(color: Palette.muted, fontSize: 12))),
                  Expanded(child: SelectableText(row[1],
                      style: const TextStyle(fontSize: 13, height: 1.35))),
                ])),
          ],
        ),
      ),
    );
  }

'''+s[b:]
s=s.replace('                      _resumeButton(),','                      _identityHeader(),\n                      _resumeButton(),',1)
# Subtle overlays on badges and collection panel
s=s.replace('color: Palette.surface,\n              border: Border.all(color: Palette.line),\n              borderRadius: BorderRadius.circular(radiusSm),', 'color: const Color(0x99171D25),\n              border: Border.all(color: const Color(0x50FFFFFF)),\n              borderRadius: BorderRadius.circular(radiusSm),',1)
# Background overlay lighter for panorama readability while keeping content legible.
s=s.replace('colors: [const Color(0x8C000000), Palette.ink.withOpacity(0.82),\n                   Palette.ink.withOpacity(0.93)],','colors: [const Color(0x77000000), Palette.ink.withOpacity(0.62),\n                   Palette.ink.withOpacity(0.88)],',1)
file.write_text(s,encoding='utf-8')
print('V20 appliquée à',file)
