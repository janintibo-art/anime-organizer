#!/usr/bin/env python3
from pathlib import Path

root=Path(__file__).resolve().parent
iss=root/'installer'/'anime_organizer.iss'
workflow=root/'.github'/'workflows'/'build.yml'
if not iss.is_file() or not workflow.is_file():
    raise SystemExit('Projet incomplet: installer/anime_organizer.iss ou .github/workflows/build.yml absent')
if not (root/'installer'/'assets'/'wizard_back.png').is_file():
    raise SystemExit('Fond de l\'installateur absent')
text=iss.read_text(encoding='utf-8-sig')
# Use default app icon, rather than the V35 replacement.
text=text.replace('SetupIconFile=..\\installer\\assets\\installer_icon.ico',
                  'SetupIconFile=..\\windows\\runner\\resources\\app_icon.ico')
# Replace the old V35 block. No bogus full GUI claims: the actual Inno theme applies on every page.
old='''WizardStyle=modern
; V35 Anime Neon Library : visuels natifs Inno Setup (BMP compatibles).
WizardImageFile=..\\installer\\assets\\wizard_side.bmp
WizardSmallImageFile=..\\installer\\assets\\wizard_small.bmp'''
new='''; V37 : Inno Setup 6.7.3, vrai style sombre avec fond sur chaque page.
; Les champs et boutons de l'assistant restent natifs et accessibles.
WizardStyle=modern dark polar includetitlebar hidebevels
WizardSizePercent=135,130
DisableWelcomePage=no
WizardBackColor=#101326
WizardBackImageFile=..\\installer\\assets\\wizard_back.png
WizardBackImageOpacity=185
; Eviter la petite vignette carre V35 et sa grande image reservee a l'accueil.
WizardImageFile=
WizardSmallImageFile='''
if old in text:
    text=text.replace(old,new,1)
elif 'WizardBackImageFile=..\\installer\\assets\\wizard_back.png' in text:
    print('Theme V37 deja installe')
else:
    raise SystemExit('Bloc de style V35 introuvable: pas de modification risquee')
iss.write_text(text,encoding='utf-8-sig')

flow=workflow.read_text(encoding='utf-8')
oldstep='''      # Inno Setup n'est pas garanti sur les machines GitHub : on l'installe
      # s'il manque. Chocolatey y est toujours present.
      - name: Installer Inno Setup si besoin
        shell: pwsh
        run: |
          $defaut = "${env:ProgramFiles(x86)}\\Inno Setup 6\\ISCC.exe"
          if (-not (Get-Command iscc -ErrorAction SilentlyContinue) -and -not (Test-Path $defaut)) {
            choco install innosetup -y --no-progress
          }

      - name: Construire l'installateur
        shell: pwsh
        run: |
          $iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
          if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\\Inno Setup 6\\ISCC.exe" }
          & $iscc "/DAppVersion=1.${{ github.run_number }}.0" "installer\\anime_organizer.iss"'''
newstep='''      # V37 : fonctionnalites WizardBackImageFile/WizardStyle necessitant Inno >= 6.7.
      # Version officielle fixee + verification SHA-256 : pas d'installateur opaque.
      - name: Preparer Inno Setup 6.7.3 verifie
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          $url = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe'
          $setup = Join-Path $env:RUNNER_TEMP 'innosetup-6.7.3.exe'
          Invoke-WebRequest -Uri $url -OutFile $setup
          $expected = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
          $actual = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLowerInvariant()
          if ($actual -ne $expected) { throw 'Empreinte Inno Setup incorrecte' }
          $dest = Join-Path $env:RUNNER_TEMP 'AnimeOrganizerInno673'
          $proc = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$dest" -PassThru -Wait
          if ($proc.ExitCode -ne 0) { throw "Installation Inno Setup en erreur ($($proc.ExitCode))" }
          $compiler = Join-Path $dest 'ISCC.exe'
          if (-not (Test-Path $compiler)) { throw 'Compilateur ISCC.exe introuvable' }
          "ANIME_ISCC=$compiler" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

      - name: Construire l'installateur
        shell: pwsh
        run: |
          & $env:ANIME_ISCC "/DAppVersion=1.${{ github.run_number }}.0" "installer\\anime_organizer.iss"'''
if oldstep in flow:
    flow=flow.replace(oldstep,newstep,1)
elif 'ANIME_ISCC' in flow:
    print('Compilateur versionne deja installe')
else:
    raise SystemExit('Etape Inno Setup attendue absente: workflow inchange')
workflow.write_text(flow,encoding='utf-8')
print('V37 appliquee : theme sombre / fond anime / icone originale / compilateur verifie')
