#!/usr/bin/env python3
"""V35: Inno Setup branding only, preserve all installation behaviour."""
from pathlib import Path

root = Path(__file__).resolve().parent
iss = root / 'installer' / 'anime_organizer.iss'
if not iss.exists():
    raise SystemExit('Erreur : installer/anime_organizer.iss introuvable.')
assets = root / 'installer' / 'assets'
required = ('wizard_side.bmp', 'wizard_small.bmp', 'installer_icon.ico')
missing = [name for name in required if not (assets / name).is_file()]
if missing:
    raise SystemExit('Erreur : visuels manquants : ' + ', '.join(missing))
text = iss.read_text(encoding='utf-8-sig')
original = text
old_icon = 'SetupIconFile=..\\windows\\runner\\resources\\app_icon.ico'
new_icon = 'SetupIconFile=..\\installer\\assets\\installer_icon.ico'
if new_icon not in text:
    if text.count(old_icon) != 1:
        raise SystemExit('Erreur : instruction SetupIconFile inattendue, aucune modification.')
    text = text.replace(old_icon, new_icon, 1)
branding = ("; V35 Anime Neon Library : visuels natifs Inno Setup (BMP compatibles).\n"
            "WizardImageFile=..\\installer\\assets\\wizard_side.bmp\n"
            "WizardSmallImageFile=..\\installer\\assets\\wizard_small.bmp\n")
if 'WizardImageFile=..\\installer\\assets\\wizard_side.bmp' not in text:
    needle='WizardStyle=modern'
    if text.count(needle)!=1:
        raise SystemExit('Erreur : WizardStyle absent ou duplique, aucune modification.')
    text=text.replace(needle,needle+'\n'+branding.rstrip(),1)
if original==text:
    print('V35 deja appliquee : aucune modification necessaire.')
else:
    iss.write_text(text,encoding='utf-8-sig',newline='\r\n')
    print('V35 appliquee : images, entete et icone Inno Setup.')
print('Les options d installation et de desinstallation sont inchangees.')
