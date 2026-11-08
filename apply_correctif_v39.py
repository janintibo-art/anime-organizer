from pathlib import Path

root = Path(__file__).resolve().parent
source = root / 'lib/screens/pc_sync_screen.dart'
if not source.is_file():
    raise SystemExit('ERREUR : fichier lib/screens/pc_sync_screen.dart introuvable dans ton projet.')
text = source.read_text(encoding='utf-8')
changes = [
    ("const Text('Copier l'invitation pour Android')", 'const Text("Copier l\'invitation pour Android")'),
    ("const Text('Coller l'invitation du PC et se connecter')", 'const Text("Coller l\'invitation du PC et se connecter")'),
]
updated = text
for old, new in changes:
    if updated.count(old) == 1:
        updated = updated.replace(old, new, 1)
        print('Corrige : ' + old)
    elif new in updated:
        print('Deja corrige : ' + new)
    else:
        raise SystemExit('ERREUR : texte attendu absent; aucun fichier modifie : ' + old)
if updated == text:
    print('Aucune modification necessaire.')
else:
    source.write_text(updated, encoding='utf-8')
    print('Correctif syntaxe Dart applique.')
