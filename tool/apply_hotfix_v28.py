#!/usr/bin/env python3
"""V28 hotfix: syntaxe galerie et raccourcis F2/F3 en lecture plein écran."""
from pathlib import Path
import os
import tempfile
import shutil

root = Path(__file__).resolve().parents[1]
changes = {}

def replace_once(src, old, new, label):
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f'{label}: ancrage attendu 1 fois, trouvé {n}. Aucun fichier modifié.')
    return src.replace(old, new, 1)

rel = 'lib/screens/detail_screen.dart'
s = (root / rel).read_text(encoding='utf-8')
if 'V28_HOTFIX_GALLERY_PARENS' not in s:
    old = 'errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))))),'
    new = 'errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)))))),'
    s = replace_once(s, old, new, 'fermeture Expanded de la galerie')
    s = replace_once(s, "  Future<void> _galleryOptions() async {", "  // V28_HOTFIX_GALLERY_PARENS: fermeture du widget Expanded corrigée.\n  Future<void> _galleryOptions() async {", 'marqueur galerie')
    changes[rel] = s

rel = 'lib/screens/player_screen.dart'
s = (root / rel).read_text(encoding='utf-8')
if 'V28_HOTFIX_FULLSCREEN_KEYS' not in s:
    s = replace_once(s,
        '    super.initState();\n    _index = widget.startIndex;',
        '    super.initState();\n    // Capture F2/F3 même lorsque les contrôles plein écran prennent le focus.\n    HardwareKeyboard.instance.addHandler(_captureFullscreenKey);\n    _index = widget.startIndex;', 'installation clavier plein écran')
    s = replace_once(s,
        '    _autoSave?.cancel();\n    _noticeTimer?.cancel();',
        '    HardwareKeyboard.instance.removeHandler(_captureFullscreenKey);\n    _autoSave?.cancel();\n    _noticeTimer?.cancel();', 'nettoyage clavier plein écran')
    needle = '  /// Raccourcis clavier, surtout utiles sous Windows.\n  void _onKey(KeyEvent event) {'
    prefix = '''  // V28_HOTFIX_FULLSCREEN_KEYS: écouteur clavier global de la fenêtre Flutter.
  // Media Kit utilise ses propres commandes en plein écran : le KeyboardListener
  // de la page ne reçoit donc pas toujours les touches F2 et F3.
  bool _captureFullscreenKey(KeyEvent event) {
    if (event is! KeyDownEvent || !Platform.isWindows || !mounted) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f2) {
      unawaited(_captureForGallery());
      return true;
    }
    if (key == LogicalKeyboardKey.f3) {
      unawaited(_captureForGallery(useAsPanorama: true));
      return true;
    }
    return false;
  }

'''
    s = replace_once(s, needle, prefix + needle, 'méthode raccourcis')
    s = replace_once(s,
        '''    if (key == LogicalKeyboardKey.f2) {
      _captureForGallery();
    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {''',
        '''    if (key == LogicalKeyboardKey.f2) {
      unawaited(_captureForGallery());
    } else if (key == LogicalKeyboardKey.f3) {
      unawaited(_captureForGallery(useAsPanorama: true));
    } else if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {''',
        'raccourci F3 classique')
    changes[rel] = s

if not changes:
    print('Correctif déjà appliqué. Aucun changement.'); raise SystemExit(0)
# Valider tous les points avant la première écriture ; écrire par fichiers temporaires.
for rel, text in changes.items():
    if not text.endswith('\n'): raise RuntimeError('Fin de fichier incorrecte : ' + rel)
for rel, text in changes.items():
    f = root / rel
    backup = f.with_suffix(f.suffix + '.pre-hotfix-v28.bak')
    if not backup.exists(): shutil.copy2(f, backup)
    fd, tmp = tempfile.mkstemp(prefix='.hotfix_v28_', dir=f.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='') as out: out.write(text)
        os.replace(tmp, f)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print('Corrigé :', rel)
