# Build rilis TerraBot Field untuk Play Console - SATU perintah.
#
#   cd D:\Repos\Terra-Nusa-Teknologi-Field
#   powershell -ExecutionPolicy Bypass -File scripts\build-rilis.ps1
#
# Berhenti di langkah pertama yang gagal, jadi AAB yang jadi selalu lolos
# analyze dan test. Flutter dan kunci tanda tangan APK hanya ada di laptop
# ini; Claude tidak dapat menjalankannya dari sesinya.

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Langkah($judul, [scriptblock]$kerja) {
    Write-Host ""
    Write-Host "==> $judul" -ForegroundColor Cyan
    & $kerja
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GAGAL: $judul" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

$versi = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
Write-Host "Versi: $versi" -ForegroundColor Yellow

if (-not (Test-Path android\app\google-services.json)) {
    Write-Host "PERINGATAN: android\app\google-services.json tidak ada - APK dibangun TANPA notifikasi HP." -ForegroundColor Yellow
}

Langkah 'flutter pub get'  { flutter pub get }
Langkah 'flutter gen-l10n' { flutter gen-l10n }
Langkah 'flutter analyze'  { flutter analyze }
Langkah 'flutter test'     { flutter test }
Langkah 'flutter build appbundle' {
    flutter build appbundle --release --dart-define=API_URL=https://services.terrabot.alphakonstruksi.id
}

$aab = 'build\app\outputs\bundle\release\app-release.aab'
$catatan = Get-ChildItem play\catatan-rilis -Filter "$($versi -replace '\+','+').txt" -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "SELESAI: $aab ($versi)" -ForegroundColor Green
if ($catatan) { Write-Host "Catatan rilis: $($catatan.FullName)" -ForegroundColor Green }
Write-Host "Sesudah diunggah ke Play: python scripts\versicek.py --sudah-unggah" -ForegroundColor Green
explorer.exe (Resolve-Path 'build\app\outputs\bundle\release')
