from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
path = root / '.github/workflows/build.yml'
s = path.read_text(encoding='utf-8')
if 'V27_SECURITY_REPORT' in s:
    print('V27 déjà appliquée'); sys.exit(0)
needle = '''      # Les noms finissent par -Windows : recuperer-apk.sh efface ce motif'''
assert s.count(needle)==1, 'Structure du workflow non reconnue : aucun fichier modifié'
insert = '''      # V27_SECURITY_REPORT: inspecter les exécutables avant publication.
      # Un hash n'est pas une preuve d'innocuité : il permet de vérifier l'intégrité.
      - name: Verification de securite Windows et empreintes SHA-256
        shell: pwsh
        run: |
          $ErrorActionPreference = 'Stop'
          New-Item -ItemType Directory -Force security-report | Out-Null
          $files = @(
            'build/windows/x64/runner/Release/anime_organizer.exe',
            'build/windows/x64/runner/Release/AnimeOrganizerSyncServer.exe',
            'build/windows/x64/runner/Release/AnimeOrganizerCreditsDetector.exe',
            'AnimeOrganizer-Windows-portable.zip'
          )
          $files += @(Get-ChildItem dist -Filter 'AnimeOrganizer-Setup-*.exe' -File | Select-Object -ExpandProperty FullName)
          foreach ($file in $files) {
            if (!(Test-Path $file)) { throw "Fichier de compilation absent : $file" }
            if ((Get-Item $file).Length -eq 0) { throw "Fichier vide : $file" }
          }
          $hashes = foreach ($file in $files) {
            $hash = Get-FileHash -Algorithm SHA256 $file
            "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path $file -Leaf)
          }
          $hashes | Set-Content security-report/windows-sha256.txt -Encoding utf8
          $status = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
          $scanner = Get-Command Start-MpScan -ErrorAction SilentlyContinue
          $report = @('Anime Organizer - rapport V27', 'Empreintes SHA-256 : windows-sha256.txt')
          if ($status -and $scanner) {
            $mp = Get-MpComputerStatus
            if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
              $report += 'Microsoft Defender : analyse personnalisée demandée.'
              foreach ($file in $files | Where-Object { $_ -like '*.exe' }) {
                Start-MpScan -ScanType CustomScan -ScanPath (Resolve-Path $file).Path
              }
              $detections = @(Get-MpThreatDetection -ErrorAction SilentlyContinue |
                Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddMinutes(-30) })
              if ($detections.Count -gt 0) {
                $report += "ATTENTION : $($detections.Count) detection(s) recentes de Defender."
                $report | Set-Content security-report/windows-analysis.txt -Encoding utf8
                throw 'Analyse Defender : detection de menace, publication interrompue.'
              }
              $report += 'Aucune detection recente remontée par Defender apres analyse.'
            } else { $report += 'Defender inactif : analyse antivirus non effectuee.' }
          } else { $report += 'Defender indisponible : analyse antivirus non effectuee.' }
          $report | Set-Content security-report/windows-analysis.txt -Encoding utf8
          Get-Content security-report/windows-analysis.txt

      - name: Publier le rapport de verification Windows
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: AnimeOrganizer-Rapport-Securite-Windows
          path: security-report/
          if-no-files-found: warn
          retention-days: 30

'''
s=s.replace(needle,insert+needle)
needle2='''      - name: Publier dans GitHub Releases
'''
assert s.count(needle2)==1
insert2='''      # V27_SECURITY_REPORT: empreinte de chaque fichier effectivement publie.
      - name: Creer les empreintes SHA-256 des telechargements
        shell: bash
        run: |
          set -euo pipefail
          cd release
          sha256sum AnimeOrganizer.apk AnimeOrganizer-Setup.exe AnimeOrganizer-Windows-portable.zip > SHA256SUMS.txt
          cat SHA256SUMS.txt
'''
s=s.replace(needle2,insert2+needle2)
path.write_text(s,encoding='utf-8')
print('V27 : verification Windows, rapport et SHA256SUMS ajoutés')
