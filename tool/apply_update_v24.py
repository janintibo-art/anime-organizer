#!/usr/bin/env python3
"""V24 - automatic categorisation and unresolved state; apply after V23."""
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
C=ROOT/'lib/services/library_controller.dart'
D=ROOT/'lib/screens/detail_screen.dart'
H=ROOT/'lib/screens/home_screen.dart'
S=ROOT/'lib/services/scanner.dart'
MARK='// V24_UNIDENTIFIED'
files=[C,D,H,S]
original={p:p.read_text(encoding='utf-8') for p in files}
if all(MARK in v for v in original.values()):
    print('V24 déjà installée.');sys.exit(0)
if not all('// V23_AUTO_CATEGORY' in original[p] for p in (C,D,S)):
    sys.exit('La V23 doit être appliquée avant la V24. Aucun fichier modifié.')
data=dict(original)
def replace(p,old,new):
    n=data[p].count(old)
    if n!=1:raise RuntimeError(f'{p.relative_to(ROOT)} : attendu 1 ancrage, trouvé {n}: {old[:90]!r}. Aucune modification.')
    data[p]=data[p].replace(old,new,1)
# An explicit unclassified state is mapped to the existing `other` filter,
# which preserves visibility in all existing UI screens and saved files.
replace(C,"    if (meta.source == 'tvmaze') return 'western';", """    // V24_UNIDENTIFIED: classify Japanese sources by provider evidence.
    if (const {'anilist', 'jikan', 'kitsu', 'animethemes', 'seed', 'index'}
        .contains(meta.source)) return 'anime';
    if (meta.source == 'tvmaze') return 'western';""")
replace(C,"    return 'anime';\n  }\n\n  /// Remet en coherence", """    // V24_UNIDENTIFIED: unknown does not mean Japanese anime.
    return 'other';
  }

  /// Remet en coherence""")
# Apply the fallback category to unresolved mismatches, not stale old metadata.
replace(C,"    anime.metaFailCount = 0;\n    // Une ancienne association fautive", """    anime.metaFailCount = 0;
    anime.category = _guessCategory(detectedTitle);
    // Une ancienne association fautive""")
# When no match is found, do not silently label the item as anime.
replace(C,"    if (meta == null) {\n      // Une panne reseau", """    if (meta == null && overrideQuery == null && !manualIds.contains(anime.id) &&
        !anime.metaFetched) {
      anime.category = _guessCategory(fileTitle ?? query);
    }
    if (meta == null) {
      // Une panne reseau""")
# Emphasize uncertainty in the existing category UI, no extra invasive panels.
replace(D,"ListTile(title: const Text('Autre animation'),", """// V24_UNIDENTIFIED: unknown files stay visible; allow manual override.
              ListTile(title: const Text('À identifier / autre animation'),""")
replace(H,"['other', 'Autres animations']", """// V24_UNIDENTIFIED: easy access to files without trusted identification.
                  ['other', 'À identifier / autres']""")
# Improve isolated-film filenames by cutting release technical tail after year.
replace(S,"      final title = cleanTitle(raw).replaceAll(RegExp(r'[._]+'), ' ').trim();\n      if (title.length >= 4) return title;", """      // V24_UNIDENTIFIED: release year and codec tags aren't title words.
      // Only cut at a year that follows a title (not films beginning with 2001).
      final normalized = cleanTitle(raw).replaceAll(RegExp(r'[._]+'), ' ').trim();
      final release = RegExp(r'\\s+(?:19[2-9]\\d|20[0-3]\\d)\\b').firstMatch(normalized);
      final title = (release == null ? normalized : normalized.substring(0, release.start)).trim();
      if (title.length >= 4) return title;""")
for p in files:
    if MARK not in data[p]:raise RuntimeError(f'Marqueur absent: {p.name}')
# Transactional: all substitutions succeeded before any write.
for p in files:
    if original[p]!=data[p]:p.write_text(data[p],encoding='utf-8')
print('V24 appliquée : catégorie À identifier et films isolés mieux nettoyés.')
