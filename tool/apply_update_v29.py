from pathlib import Path
import sys
root = Path(__file__).resolve().parents[1]
wf = root / '.github/workflows/build.yml'
audit = root / 'tool/audit_windows_v29.ps1'
if not wf.exists() or not audit.exists():
    raise SystemExit('Projet incomplet : workflow ou audit absent.')
text = wf.read_text(encoding='utf-8')
marker = '      # V29_INDIVIDUAL_AUDIT: rapport separant signature, integrite et antivirus.'
if marker in text:
    print('V29 deja appliquee.'); sys.exit(0)
start = '      # V27_SECURITY_REPORT: inspecter les exécutables avant publication.'
end = '      - name: Publier le rapport de verification Windows'
if text.count(start) != 1 or text.count(end) != 1:
    raise RuntimeError('Le workflow a change : audit V27 introuvable, aucune modification effectuee.')
a, b = text.index(start), text.index(end)
if a >= b:
    raise RuntimeError('Structure des etapes invalidee : aucun changement.')
replacement = '''      # V29_INDIVIDUAL_AUDIT: rapport separant signature, integrite et antivirus.
      # Si Defender est inactif, l'etat reste UNVERIFIED : jamais "sans virus".
      - name: Auditer chaque executable Windows (V29)
        shell: pwsh
        run: ./tool/audit_windows_v29.ps1

'''
updated = text[:a] + replacement + text[b:]
wf.write_text(updated, encoding='utf-8')
print('V29 appliquee : audit par fichier et publication du rapport conserves.')
