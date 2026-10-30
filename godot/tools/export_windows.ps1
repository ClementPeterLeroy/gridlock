param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$repoPath = Split-Path -Parent $projectPath
$packagePath = Join-Path $repoPath 'dist/gridlock-v3.0-beta.2-windows'
New-Item -ItemType Directory -Force -Path $packagePath | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath '.godot') | Out-Null
$exportLog = Join-Path $projectPath '.godot/export-windows.log'
& $Godot --headless --path $projectPath --export-release 'Windows Desktop' (Join-Path $packagePath 'Gridlock.exe') --log-file $exportLog
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $packagePath 'Gridlock.exe'))) {
    throw 'Windows export failed. Install matching Godot export templates using Editor > Manage Export Templates, then retry. No release ZIP was created.'
}
if (!(Test-Path -LiteralPath (Join-Path $packagePath 'Gridlock.pck'))) {
    throw 'The companion Gridlock.pck is missing; do not distribute this directory.'
}
Copy-Item -LiteralPath (Join-Path $projectPath 'distribution/README.txt') -Destination $packagePath
Copy-Item -LiteralPath (Join-Path $projectPath 'distribution/THIRD_PARTY_NOTICES.txt') -Destination $packagePath
foreach ($fontLicense in @('Cinzel-OFL.txt', 'Lato-OFL.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectPath "assets/fonts/$fontLicense") -Destination $packagePath
}
& $Godot --headless --path $projectPath --script res://tools/export_notices.gd --log-file $exportLog -- --output (Join-Path $packagePath 'GODOT_COPYRIGHT.txt')
if ($LASTEXITCODE -ne 0) { throw 'Engine notice generation failed; do not distribute this directory.' }
$rootLicense = Join-Path $repoPath 'LICENSE'
if (Test-Path -LiteralPath $rootLicense) { Copy-Item -LiteralPath $rootLicense -Destination $packagePath }
Compress-Archive -Path (Join-Path $packagePath '*') -DestinationPath "$packagePath.zip" -Force
Write-Output "Created $packagePath.zip. Launch Gridlock.exe outside the editor before distribution."
