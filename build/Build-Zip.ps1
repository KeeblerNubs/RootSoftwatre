#Requires -Version 5.1
<#
  Stages the repository (source only) and produces a versioned ZIP in .\dist
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Version  = '1.0.0'
$Name     = "FOXXD-A67L-Gen2-Toolkit-v$Version"
$Dist     = Join-Path $RepoRoot 'dist'
$Stage    = Join-Path $Dist $Name
$ZipPath  = Join-Path $Dist "$Name.zip"

if (Test-Path $Stage)  { Remove-Item $Stage -Recurse -Force }
if (Test-Path $ZipPath){ Remove-Item $ZipPath -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

$include = @(
    'README.md','LICENSE','CHANGELOG.md','CONTRIBUTING.md','.gitignore',
    'src','build','docs'
)
foreach ($item in $include) {
    $source = Join-Path $RepoRoot $item
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $Stage -Recurse -Force
    }
}

# Placeholder so users know where platform-tools go
$toolsDir = Join-Path $Stage 'tools'
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
@'
Place Android Platform-Tools for Windows in this folder:

  platform-tools\adb.exe
  platform-tools\fastboot.exe
  platform-tools\*.dll

Download: https://developer.android.com/tools/releases/platform-tools
Not bundled: Google's licence does not permit redistribution.
The toolkit auto-detects .\tools\ and .\tools\platform-tools\.
'@ | Set-Content -Path (Join-Path $toolsDir 'README.txt') -Encoding UTF8

Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $ZipPath -CompressionLevel Optimal

$hash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
Set-Content -Path "$ZipPath.sha256" -Value ("{0}  {1}" -f $hash, (Split-Path $ZipPath -Leaf)) -Encoding ASCII
Remove-Item $Stage -Recurse -Force

Write-Host "Built: $ZipPath" -ForegroundColor Green
Write-Host "SHA256: $hash" -ForegroundColor Green
