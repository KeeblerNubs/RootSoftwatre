#Requires -Version 5.1
<#
  FOXXD A67L Gen2 Rooting Toolkit  v1.0.0
  READ-ONLY build: no unlock, no erase, no flash.
#>
[CmdletBinding()]
param(
    [switch]$Diagnostics,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$Root       = Split-Path -Parent $PSScriptRoot
$Expected   = 'Android16_Foxxd_A67L_3G_V1.0_260530'
$Stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportDir  = Join-Path $Root "reports\$Stamp"
$LogPath    = Join-Path $ReportDir 'report.txt'
$JsonPath   = Join-Path $ReportDir 'report.json'
$script:Log = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    $script:Log.Add($line)
}

function Get-Tool {
    param([string]$Name)
    $candidates = @(
        (Join-Path $Root "tools\$Name.exe"),
        (Join-Path $Root "tools\platform-tools\$Name.exe")
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Adb {
    param($Adb, [string[]]$Arguments, [string]$Serial)
    $adbArguments = @()
    if ($Serial) { $adbArguments += @('-s', $Serial) }
    $adbArguments += $Arguments
    $out = & $Adb @adbArguments 2>&1
    return ($out | Out-String).Trim()
}

function Get-DeviceProps {
    param($Adb, [string]$Serial)
    $keys = @(
        'ro.build.fingerprint','ro.product.brand','ro.product.model','ro.product.device',
        'ro.board.platform','ro.hardware','ro.boot.hardware','ro.boot.slot_suffix',
        'ro.boot.flash.locked','ro.boot.verifiedbootstate','ro.boot.veritymode',
        'ro.build.version.release','ro.build.version.sdk','ro.build.id',
        'ro.build.date','ro.product.cpu.abi','ro.treble.enabled'
    )
    $props = [ordered]@{}
    foreach ($k in $keys) {
        $v = Invoke-Adb -Adb $Adb -Arguments @('shell','getprop',$k) -Serial $Serial
        if ([string]::IsNullOrWhiteSpace($v)) { $v = '<not reported>' }
        $props[$k] = $v
    }
    return $props
}

function Get-PartitionProbe {
    param($Adb, [string]$Serial)
    $raw = Invoke-Adb -Adb $Adb -Arguments @('shell','ls','-1','/dev/block/by-name/') -Serial $Serial
    $names = @()
    if ($raw -match 'Permission denied' -or $raw -match 'No such file') {
        $raw = Invoke-Adb -Adb $Adb -Arguments @('shell','ls','-1','/dev/block/bootdevice/by-name/') -Serial $Serial
    }
    foreach ($token in ($raw -split "`r?`n")) {
        $t = $token.Trim()
        if ($t -and $t -notmatch '\s' -and $t -notmatch 'Permission|denied|error') { $names += $t }
    }
    return ($names | Sort-Object -Unique)
}

function Resolve-RamdiskPlan {
    param([string[]]$Partitions)
    $joined = ($Partitions -join ' ')
    if ($joined -match 'init_boot') {
        return [ordered]@{
            RamdiskPartition = 'init_boot'
            PatchTarget      = 'init_boot.img'
            Confidence       = 'high'
            Rationale        = 'init_boot partition present: Android 13+ GKI layout, ramdisk isolated.'
        }
    }
    if ($joined -match '(^|\s)boot(_a|_b)?(\s|$)') {
        return [ordered]@{
            RamdiskPartition = 'boot'
            PatchTarget      = 'boot.img'
            Confidence       = 'medium'
            Rationale        = 'No init_boot found; ramdisk expected inside boot image.'
        }
    }
    return [ordered]@{
        RamdiskPartition = 'unknown'
        PatchTarget      = $null
        Confidence       = 'none'
        Rationale        = 'Partition list unavailable (SELinux). Re-run after unlock or use a supported dump method.'
    }
}

function Get-PackageInventory {
    param($Adb, [string]$OutFile, [string]$Serial)
    $pkgs = Invoke-Adb -Adb $Adb -Arguments @('shell','cmd','package','list','packages','-f') -Serial $Serial
    Set-Content -Path $OutFile -Value $pkgs -Encoding UTF8
    return (($pkgs -split "`r?`n") | Where-Object { $_ -match '^package:' }).Count
}

function Save-Sha256Manifest {
    param([string]$Dir)
    $manifest = Join-Path $Dir 'SHA256SUMS.txt'
    $entries = @()
    Get-ChildItem -Path $Dir -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | ForEach-Object {
        $h = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
        $entries += ("{0}  {1}" -f $h, $_.Name)
    }
    Set-Content -Path $manifest -Value $entries -Encoding ASCII
    Write-Log "SHA-256 manifest written: $manifest"
}

function Invoke-Diagnostics {
    param([string]$OnlySerial)

    $adb = Get-Tool 'adb'
    if (-not $adb) {
        Write-Log 'ERROR: adb.exe not found. Place platform-tools in .\tools\ or add to PATH.' 'Red'
        throw 'ADB was not found.'
    }

    Write-Log "Using adb: $adb"
    $deviceList = Invoke-Adb -Adb $adb -Arguments @('devices')
    Write-Log "adb devices ->`n$deviceList"

    $ready = @()
    foreach ($line in ($deviceList -split "`r?`n")) {
        if ($line -match '^(\S+)\s+device$') { $ready += $Matches[1] }
        elseif ($line -match '^(\S+)\s+unauthorized$') {
            Write-Log "Device $($Matches[1]) is UNAUTHORIZED - accept the RSA prompt on the phone." 'Yellow'
        }
    }
    if (-not $ready) {
        Write-Log 'No authorized device connected. Accept the USB debugging prompt and try again.' 'Red'
        throw 'No authorized ADB device was found.'
    }

    if ($OnlySerial) {
        $ready = @($ready | Where-Object { $_ -eq $OnlySerial })
        if (-not $ready) {
            Write-Log "No authorized device found with serial $OnlySerial." 'Red'
            throw "No authorized ADB device found with serial $OnlySerial."
        }
    }

    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

    $allReports = @()
    foreach ($serial in $ready) {
        Write-Log "===== Device $serial =====" 'Cyan'

        $props = Get-DeviceProps $adb $serial
        foreach ($k in $props.Keys) { Write-Log ("  {0} = {1}" -f $k, $props[$k]) }

        $buildMatch = ($props['ro.build.fingerprint'] -eq $Expected) -or
                      ($props['ro.build.id'] -eq $Expected)
        if ($buildMatch) { Write-Log "  Build matches expected: $Expected" 'Green' }
        else { Write-Log "  WARNING: build differs from expected $Expected" 'Yellow' }

        Write-Log '  --- Partition layout ---' 'Cyan'
        $parts = Get-PartitionProbe $adb $serial
        if ($parts.Count -eq 0) { Write-Log '  Partition list unavailable (SELinux restriction).' 'Yellow' }
        foreach ($p in $parts) { Write-Log "  $p" }

        $plan = Resolve-RamdiskPlan $parts
        Write-Log ("  Ramdisk partition : {0}" -f $plan.RamdiskPartition) 'Green'
        Write-Log ("  Magisk patch target: {0}" -f $plan.PatchTarget)
        Write-Log ("  Confidence        : {0}" -f $plan.Confidence)
        Write-Log ("  Rationale         : {0}" -f $plan.Rationale)

        Write-Log '  --- Bootloader / verified boot ---' 'Cyan'
        $locked = $props['ro.boot.flash.locked']
        $vb     = $props['ro.boot.verifiedbootstate']
        $bootloaderState = 'unknown'
        if ($locked -eq '1') { $bootloaderState = 'locked'; Write-Log '  Bootloader LOCKED: unlock required before any flash.' 'Yellow' }
        elseif ($locked -eq '0') { $bootloaderState = 'unlocked'; Write-Log '  Bootloader UNLOCKED.' 'Green' }
        else { Write-Log "  Bootloader state not reported ($locked)." 'Yellow' }
        Write-Log "  verifiedbootstate = $vb"
        if ($vb -eq 'orange') { Write-Log '  Verified boot is permissive (orange) - expect warnings on boot.' 'Yellow' }

        Write-Log '  --- Snapshot ---' 'Cyan'
        $logcat = Join-Path $ReportDir "logcat_$serial.txt"
        Invoke-Adb -Adb $adb -Arguments @('logcat','-d') -Serial $serial | Set-Content -Path $logcat -Encoding UTF8
        Write-Log "  logcat -> $logcat"

        $pkgFile = Join-Path $ReportDir "packages_$serial.txt"
        $pkgCount = Get-PackageInventory $adb $pkgFile $serial
        Write-Log "  packages: $pkgCount entries -> $pkgFile"

        $settings = Join-Path $ReportDir "settings_$serial.txt"
        $snapshot = @(
            (Invoke-Adb -Adb $adb -Arguments @('shell','settings','list','global') -Serial $serial),
            (Invoke-Adb -Adb $adb -Arguments @('shell','dumpsys','package','|','grep','-c','Package') -Serial $serial),
            (Invoke-Adb -Adb $adb -Arguments @('shell','df','-h') -Serial $serial)
        ) -join "`n`n"
        Set-Content -Path $settings -Value $snapshot -Encoding UTF8

        $allReports += [ordered]@{
            serial          = $serial
            timestamp       = (Get-Date).ToString('s')
            expectedBuild   = $Expected
            buildMatches    = $buildMatch
            properties      = $props
            partitions      = $parts
            ramdiskPlan     = $plan
            bootloaderState = $bootloaderState
            verifiedBoot    = $vb
            packageCount    = $pkgCount
            artifacts       = @("logcat_$serial.txt","packages_$serial.txt","settings_$serial.txt")
        }
    }

    $payload = [ordered]@{
        toolkit = 'FOXXD-A67L-Gen2-Toolkit'
        version = '1.0.0'
        mode    = 'read-only'
        host    = $env:COMPUTERNAME
        os      = [System.Environment]::OSVersion.VersionString
        devices = $allReports
        log     = $script:Log
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $JsonPath -Encoding UTF8
    Set-Content -Path $LogPath -Value $script:Log -Encoding UTF8
    Save-Sha256Manifest $ReportDir

    Write-Log "Report directory: $ReportDir" 'Green'
    Write-Log 'NEXT: no flashing. Send report.json for layout confirmation.' 'Yellow'
}

function Show-RootReadiness {
    Write-Host ''
    Write-Host '=== Magisk Readiness Checklist ===' -ForegroundColor Green
    Write-Host @'
1. Magisk v31.1 is the current stable release; it adds Android 16 QPR2
   sepolicy and Zygisk support. Get it from the official GitHub releases.

2. Bootloader unlock. Unisoc SC9863A platforms frequently reject
   `fastboot flashing unlock` without a vendor auth file. Test only when
   you accept a full data wipe:
       fastboot flashing unlock

3. Stock image first. Never patch a boot image you did not dump or
   download for THIS build (Android16_Foxxd_A67L_3G_V1.0_260530).

4. Patch with the Magisk app ("Select and Patch a File") using the target
   named by the diagnostics (boot.img or init_boot.img), then flash:
       fastboot flash init_boot magisk_patched-*.img

5. Recovery route. Keep the untouched stock image; a bootloop is fixed by
       fastboot flash init_boot stock_init_boot.img
   No flash without this file on disk and hash-recorded.

6. Verify after boot: `adb shell su -v` and Magisk app shows installed version.
'@ -ForegroundColor White
    Write-Host ''
}

function Show-Menu {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host '  FOXXD A67L Gen2 Rooting Toolkit  v1.0.0' -ForegroundColor Cyan
    Write-Host '  Target : Android16_Foxxd_A67L_3G_V1.0_260530' -ForegroundColor Cyan
    Write-Host '  Mode   : READ-ONLY (flashing disabled)' -ForegroundColor Yellow
    Write-Host '==================================================' -ForegroundColor Cyan
    Write-Host ' 1) Device diagnostics + snapshot'
    Write-Host ' 2) Magisk readiness checklist'
    Write-Host ' 3) Quit'
}

if ($Diagnostics) {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    Invoke-Diagnostics -OnlySerial $Serial
    exit 0
}

while ($true) {
    Show-Menu
    $choice = Read-Host 'Select'
    switch ($choice) {
        '1' { New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
              Invoke-Diagnostics -OnlySerial $Serial
              Read-Host 'Press Enter' | Out-Null }
        '2' { Show-RootReadiness; Read-Host 'Press Enter' | Out-Null }
        '3' { break }
        default { }
    }
}
