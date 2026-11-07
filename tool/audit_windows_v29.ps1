# Anime Organizer V29 - executable-by-executable audit. No security bypass.
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path 'security-report' | Out-Null
$release = 'build/windows/x64/runner/Release'
$files = @(
  "$release/anime_organizer.exe",
  "$release/AnimeOrganizerSyncServer.exe",
  "$release/AnimeOrganizerCreditsDetector.exe",
  'AnimeOrganizer-Windows-portable.zip'
)
$installers = @(Get-ChildItem -Path 'dist' -Filter 'AnimeOrganizer-Setup-*.exe' -File -ErrorAction Stop)
if ($installers.Count -eq 0) { throw 'Installateur Windows absent : audit impossible.' }
$files += @($installers | ForEach-Object { $_.FullName })
foreach ($file in $files) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Fichier attendu absent : $file" }
  if ((Get-Item -LiteralPath $file).Length -eq 0) { throw "Fichier vide : $file" }
}
$sha = foreach ($file in $files) {
  $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
  '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), (Split-Path $file -Leaf)
}
$sha | Set-Content -Path 'security-report/windows-sha256.txt' -Encoding UTF8

$defenderState = 'NOT_AVAILABLE'
$defenderReason = 'Commandes Defender absentes sur le runner.'
try {
  $statusCmd = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
  $scanCmd = Get-Command Start-MpScan -ErrorAction SilentlyContinue
  $threatCmd = Get-Command Get-MpThreatDetection -ErrorAction SilentlyContinue
  if ($statusCmd -and $scanCmd -and $threatCmd) {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
      $defenderState = 'READY'
      $defenderReason = 'Defender actif : chaque EXE sera analyse.'
    } else {
      $defenderState = 'DISABLED'
      $defenderReason = 'Defender inactif : aucun verdict antivirus possible.'
    }
  }
} catch {
  $defenderState = 'ERROR'
  $defenderReason = "Consultation Defender impossible : $($_.Exception.Message)"
}

$results = @()
$detected = $false
foreach ($file in $files) {
  $obj = Get-Item -LiteralPath $file
  $full = $obj.FullName
  $name = $obj.Name
  $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
  $signature = 'NOT_APPLICABLE'
  $scanStatus = 'NOT_SCANNED'
  $details = 'Archive ZIP : controle antivirus non effectue sur ce fichier.'
  if ($obj.Extension -ieq '.exe') {
    try {
      $signature = (Get-AuthenticodeSignature -LiteralPath $full -ErrorAction Stop).Status.ToString()
    } catch { $signature = 'ERROR' }
    if ($defenderState -eq 'READY') {
      $scanStarted = Get-Date
      try {
        Start-MpScan -ScanType CustomScan -ScanPath $full -ErrorAction Stop
        $threats = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object {
          $_.InitialDetectionTime -ge $scanStarted.AddSeconds(-3)
        })
        if ($threats.Count -gt 0) {
          $scanStatus = 'DETECTED'
          $details = "Defender : $($threats.Count) nouvelle(s) detection(s) pendant l'analyse de ce fichier."
          $detected = $true
        } else {
          $scanStatus = 'NO_DETECTION'
          $details = 'Analyse Defender effectuee : aucune detection nouvelle signalee.'
        }
      } catch {
        $scanStatus = 'SCAN_ERROR'
        $details = "Analyse Defender en echec : $($_.Exception.Message)"
      }
    } else {
      $details = $defenderReason
    }
  }
  $results += [pscustomobject]@{
    file = $name
    size_bytes = $obj.Length
    sha256 = $hash
    authenticode = $signature
    antivirus = $scanStatus
    note = $details
  }
}
$overall = if ($detected) { 'DETECTED' } elseif (@($results | Where-Object { $_.antivirus -eq 'SCAN_ERROR' }).Count -gt 0) {
  'SCAN_ERROR'
} elseif (@($results | Where-Object { $_.antivirus -eq 'NO_DETECTION' }).Count -eq 4) {
  'ANALYZED_NO_DETECTION'
} else { 'UNVERIFIED' }
$metadata = [pscustomobject]@{
  report_version = 29
  generated_utc = (Get-Date).ToUniversalTime().ToString('o')
  github_commit = $env:GITHUB_SHA
  github_run_id = $env:GITHUB_RUN_ID
  overall = $overall
  defender = $defenderState
  defender_explanation = $defenderReason
  note = 'Une absence de detection ne prouve pas qu un fichier est sur. Les fichiers ZIP ne sont pas analyses directement.'
  files = $results
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content 'security-report/windows-analysis.json' -Encoding UTF8
$lines = @(
  'Anime Organizer - rapport de verification V29',
  "STATUT GLOBAL : $overall",
  "Defender : $defenderState",
  $defenderReason,
  'IMPORTANT : NOT_SCANNED et UNVERIFIED ne signifient PAS sain.',
  'Authenticode NotSigned = non signe, pas preuve de malware.',
  'Empreintes : windows-sha256.txt',
  ''
)
foreach ($r in $results) {
  $lines += "$($r.file) | $($r.antivirus) | signature: $($r.authenticode) | SHA256: $($r.sha256)"
  $lines += "  $($r.note)"
}
$lines | Set-Content 'security-report/windows-analysis.txt' -Encoding UTF8
Get-Content 'security-report/windows-analysis.txt'
if ($detected) { throw 'Menace signalee par Defender : publication interrompue.' }
# Leave build usable if Defender is disabled, but never label it virus-free.
