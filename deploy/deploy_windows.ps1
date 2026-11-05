# Deploy IMAGO web dari Windows.
#
# Flutter yang dipanggil dari Git Bash gagal mengompilasi ("Error when reading
# .../Pub/Cache/..."), jadi pembagiannya:
#   1. pustaka web diambil dan diperiksa SHA-256-nya (Git Bash)
#   2. build web dari PowerShell
#   3. pengiriman ke server oleh deploy.sh dengan SKIP_BUILD=1 (Git Bash)
#
# Jalankan dari PowerShell, di folder mana pun:
#   .\deploy\deploy_windows.ps1
#   .\deploy\deploy_windows.ps1 -VpsHost user@host

param(
  [string]$VpsHost = 'svr-app-prd-imago@10.30.12.65'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$bash = 'C:\Program Files\Git\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "Git Bash tidak ditemukan di $bash" }

Write-Host '==> Ambil pustaka web (diperiksa SHA-256)'
& $bash tool/fetch_web_vendor.sh
if ($LASTEXITCODE -ne 0) { throw 'fetch_web_vendor.sh gagal; deploy dihentikan.' }

Write-Host '==> Build web (PowerShell)'
& flutter build web --release --no-web-resources-cdn
if ($LASTEXITCODE -ne 0) { throw 'flutter build web gagal; deploy dihentikan.' }

$env:VPS_HOST = $VpsHost
$env:SKIP_BUILD = '1'
try {
  & $bash deploy/deploy.sh
  if ($LASTEXITCODE -ne 0) { throw "deploy.sh gagal (kode $LASTEXITCODE)." }
} finally {
  Remove-Item Env:SKIP_BUILD -ErrorAction SilentlyContinue
}
