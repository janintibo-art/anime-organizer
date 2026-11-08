#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
source = root / 'lib/screens/player_screen.dart'
if not source.is_file():
    print(f'Erreur : fichier manquant : {source}', file=sys.stderr)
    sys.exit(1)
text = source.read_text(encoding='utf-8')
old = """        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Nouvel extrait enregistre : ${p.basename(path)}'),
"""
new = """        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Nouvel extrait enregistre : ${p.basename(path)}'),
"""
if old in text:
    if text.count(old) != 1:
        sys.exit('Erreur : bloc trouve plusieurs fois, correction abandonnee.')
    source.write_text(text.replace(old, new, 1), encoding='utf-8')
    print('V34 : erreur const SnackBar corrigee dans player_screen.dart.')
elif new in text:
    print('V34 : correction deja presente, aucun changement.')
else:
    sys.exit('Erreur : version inattendue du code ; aucune modification appliquee.')
