#!/usr/bin/env python3
"""Correction syntaxique V32 : une parenthèse surnuméraire autour du panneau musique."""
from pathlib import Path

file = Path(__file__).resolve().parent / 'lib/screens/detail_screen.dart'
if not file.exists():
    raise SystemExit(f'Fichier absent : {file}. Vérifie le dossier du projet.')
text = file.read_text(encoding='utf-8')
old = "          ]))),\n      )),\n    );\n  }\n\n  Future<void> _reloadGallery() async {"
new = "          ]))),\n      ),\n    );\n  }\n\n  Future<void> _reloadGallery() async {"
if old in text:
    text = text.replace(old, new, 1)
    file.write_text(text, encoding='utf-8')
    print('OK : parenthèse V32 corrigée dans detail_screen.dart')
elif new in text:
    print('OK : correctif déjà présent ; aucune modification.')
else:
    raise SystemExit('La structure du fichier a changé. Correctif arrêté sans modification.')
