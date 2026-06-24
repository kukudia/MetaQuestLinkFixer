param(
    [string]$Version = "dev"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$distDir = Join-Path $repoRoot "dist"
$packageName = "MetaQuestLinkFixer-$Version"
$packageDir = Join-Path $distDir $packageName
$zipPath = Join-Path $distDir "$packageName.zip"

if (Test-Path -LiteralPath $packageDir) {
    Remove-Item -LiteralPath $packageDir -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

foreach ($file in @(
    "Fix-MetaQuestLink.ps1",
    "Run-MetaQuestLinkFixer.cmd",
    "MetaQuestLinkFixer.ico",
    "README.md",
    "README.txt",
    "LICENSE"
)) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination $packageDir -Force
}

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $zipPath -Force
Write-Host "Created $zipPath"
