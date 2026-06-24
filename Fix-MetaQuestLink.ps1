<#
Meta Quest Link one-click repair for this PC.
Run from the desktop shortcut. The script elevates itself, repairs common
Meta Horizon update regressions, then writes a log under D:\MetaQuestLinkFixer\Logs.
#>

param(
    [switch]$SkipClientCacheReset,
    [switch]$SkipClientLaunch,
    [switch]$NoMessageBox
)

$ErrorActionPreference = "Continue"

$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $InstallDir "Logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss-ffff"
$LogPath = Join-Path $LogDir "MetaQuestLinkFix-$Stamp.log"
$LogEncoding = New-Object System.Text.UTF8Encoding($false)

function Write-Step {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Write-Host $line

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine, $LogEncoding)
            return
        } catch {
            if ($attempt -eq 5) {
                Write-Warning "Could not write to log after 5 attempts: $($_.Exception.Message)"
                return
            }
            Start-Sleep -Milliseconds 150
        }
    }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-MetaProcesses {
    $knownNames = @(
        "OVRServer_x64",
        "OVRRedir",
        "OVRServiceLauncher",
        "OculusClient",
        "Client",
        "OculusDash",
        "RemoteDesktopCompanion",
        "MQRDCrashpadHandler"
    )

    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $path = ""
        try { $path = [string]$_.Path } catch {}

        $knownNames -contains $_.ProcessName -or
            $path.StartsWith("D:\Meta Horizon\", [System.StringComparison]::OrdinalIgnoreCase)
    }

    foreach ($process in $processes) {
        Write-Step "Stopping process: $($process.ProcessName) ($($process.Id))"
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        } catch {
            Write-Step "WARNING: Could not stop $($process.ProcessName) ($($process.Id)): $($_.Exception.Message)"
        }
    }
}

function Backup-And-ResetDirectory {
    param(
        [string]$Path,
        [string]$Reason
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Step "Skipped missing cache directory: $Path"
        return $null
    }

    $backupRoot = Join-Path $LogDir "ClientCacheBackups"
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

    $leaf = Split-Path -Leaf $Path
    $safeLeaf = $leaf -replace '[^A-Za-z0-9._-]', '_'
    $backupPath = Join-Path $backupRoot "$safeLeaf-$Stamp"

    try {
        Move-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction Stop
        Write-Step "Reset client cache ($Reason): $Path -> $backupPath"
        return $backupPath
    } catch {
        Write-Step "WARNING: Could not reset client cache ${Path}: $($_.Exception.Message)"
        return $null
    }
}

function Get-LatestOculusClientError {
    $errorDir = Join-Path $env:APPDATA "Oculus"
    if (-not (Test-Path -LiteralPath $errorDir -PathType Container)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $errorDir -Filter "OculusClientError-*.txt" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Test-RecentSplashCrash {
    $latestError = Get-LatestOculusClientError
    if (-not $latestError) {
        return $false
    }

    if ($latestError.LastWriteTime -lt (Get-Date).AddHours(-12)) {
        return $false
    }

    try {
        $text = Get-Content -LiteralPath $latestError.FullName -Raw -ErrorAction Stop
        return ($text -match "getViewerContext|Crash occured while splash screen was up|Object has been destroyed|QLH is already running")
    } catch {
        return $false
    }
}

function Start-UserProcess {
    param([string]$FilePath)

    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.ShellExecute($FilePath, "", (Split-Path -Parent $FilePath), "open", 1)
        Write-Step "Meta Horizon client launch requested via Explorer shell: $FilePath"
        return $true
    } catch {
        Write-Step "WARNING: Explorer-shell launch failed: $($_.Exception.Message)"
        try {
            Start-Process -FilePath $FilePath -ErrorAction Stop
            Write-Step "Meta Horizon client launch requested directly: $FilePath"
            return $true
        } catch {
            Write-Step "WARNING: Direct client launch failed: $($_.Exception.Message)"
            return $false
        }
    }
}

function Set-GpuPreference {
    param(
        [string]$RegistryPath,
        [string]$AppPath
    )

    try {
        New-Item -Path $RegistryPath -Force | Out-Null
        New-ItemProperty -Path $RegistryPath -Name $AppPath -PropertyType String -Value "GpuPreference=2;" -Force | Out-Null
        Write-Step "GPU preference set ($RegistryPath): $AppPath"
        return $true
    } catch {
        Write-Step "WARNING: Could not set GPU preference ($RegistryPath) for ${AppPath}: $($_.Exception.Message)"
        return $false
    }
}

function Get-LastJsonStringValue {
    param(
        [string]$Text,
        [string]$Name,
        [switch]$PreferNonEmpty
    )

    $escapedName = [regex]::Escape($Name)
    $matches = [regex]::Matches($Text, '"' + $escapedName + '"\s*:\s*"([^"]*)"')
    if ($matches.Count -eq 0) {
        return ""
    }

    if ($PreferNonEmpty) {
        for ($i = $matches.Count - 1; $i -ge 0; $i--) {
            $value = $matches[$i].Groups[1].Value.Trim()
            if ($value) {
                return $value
            }
        }
    }

    return $matches[$matches.Count - 1].Groups[1].Value.Trim()
}

function Get-LatestOculusCompatibilitySummary {
    $oculusLocalDir = Join-Path $env:LOCALAPPDATA "Oculus"
    if (-not (Test-Path -LiteralPath $oculusLocalDir -PathType Container)) {
        return "Latest Meta compatibility: no local Oculus log directory found."
    }

    $latestPerfLog = Get-ChildItem -LiteralPath $oculusLocalDir -Filter "PerfLog_*.json" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestPerfLog) {
        return "Latest Meta compatibility: no PerfLog_*.json found."
    }

    try {
        $text = Get-Content -LiteralPath $latestPerfLog.FullName -Raw -ErrorAction Stop
    } catch {
        return "Latest Meta compatibility: could not read $($latestPerfLog.FullName): $($_.Exception.Message)"
    }

    $overallCompat = Get-LastJsonStringValue -Text $text -Name "overall_compat"
    $cpuNames = Get-LastJsonStringValue -Text $text -Name "cpu_names" -PreferNonEmpty
    $cpuCompat = Get-LastJsonStringValue -Text $text -Name "cpu_compat"
    $gpuNames = Get-LastJsonStringValue -Text $text -Name "gpu_names" -PreferNonEmpty
    $gpuCompat = Get-LastJsonStringValue -Text $text -Name "gpu_compat"
    $gpuVram = Get-LastJsonStringValue -Text $text -Name "gpu_vram"
    $gpuDriver = Get-LastJsonStringValue -Text $text -Name "gpu_driver"
    $hmdGpu = Get-LastJsonStringValue -Text $text -Name "hmd_graphics_adapter_desc" -PreferNonEmpty
    $hmdGpuDriver = Get-LastJsonStringValue -Text $text -Name "hmd_graphics_adapter_driver" -PreferNonEmpty
    $systemMemoryCompat = Get-LastJsonStringValue -Text $text -Name "system_memory_compat"
    $osCompat = Get-LastJsonStringValue -Text $text -Name "os_compat"
    $usbCompat = Get-LastJsonStringValue -Text $text -Name "usb_compat"

    $summaryLines = @(
        "Latest Meta compatibility log: $($latestPerfLog.FullName)",
        "overall_compat = $overallCompat",
        "cpu = $cpuCompat ($cpuNames)",
        "gpu_compat = $gpuCompat",
        "gpu_names = $gpuNames",
        "gpu_vram_mib = $gpuVram",
        "gpu_driver = $gpuDriver",
        "hmd_graphics_adapter = $hmdGpu",
        "hmd_graphics_driver = $hmdGpuDriver",
        "system_memory/os/usb = $systemMemoryCompat / $osCompat / $usbCompat"
    )

    foreach ($line in $summaryLines) {
        Write-Step $line
    }

    if ($hmdGpu -match "NVIDIA" -or $gpuCompat -match "PASS") {
        Write-Step "Compatibility note: Meta is seeing the NVIDIA adapter, but overall compatibility can still fail because CPU or another enumerated adapter fails Meta's whitelist."
    }

    return ($summaryLines -join [Environment]::NewLine)
}

if (-not (Test-Admin)) {
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`""
    )

    if ($SkipClientCacheReset) { $args += "-SkipClientCacheReset" }
    if ($SkipClientLaunch) { $args += "-SkipClientLaunch" }
    if ($NoMessageBox) { $args += "-NoMessageBox" }

    Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs
    exit
}

Write-Step "Meta Quest Link repair started."

$OculusRuntime = "D:\Meta Horizon\Support\oculus-runtime\oculus_openxr_64.json"
$OculusClient = "D:\Meta Horizon\Support\oculus-client\Client.exe"
$OculusDriver = "D:\Meta Horizon\Support\oculus-drivers\oculus-driver.exe"
$CrashAfterLaunch = $false
$LatestCrashPath = ""
$CacheBackups = @()

if (-not (Test-Path -LiteralPath $OculusRuntime)) {
    Write-Step "ERROR: Oculus OpenXR runtime not found: $OculusRuntime"
    Write-Step "Repair cannot continue until Meta Horizon is installed at D:\Meta Horizon."
    Read-Host "Meta Horizon runtime not found. Press Enter to close"
    exit 1
}

Write-Step "Stopping Oculus processes and service."
try { Stop-Service OVRService -Force -ErrorAction SilentlyContinue } catch {}
Stop-MetaProcesses
Start-Sleep -Seconds 2

if (-not $SkipClientCacheReset) {
    $shouldResetClientCache = Test-RecentSplashCrash
    if ($shouldResetClientCache) {
        Write-Step "Recent Meta Horizon splash crash detected; resetting Electron client cache."
        $clientCache = Join-Path $env:APPDATA "Client"
        $metaQuestLinkCache = Join-Path $env:APPDATA "Meta Quest Link"
        $CacheBackups += Backup-And-ResetDirectory -Path $clientCache -Reason "recent splash crash"
        $CacheBackups += Backup-And-ResetDirectory -Path $metaQuestLinkCache -Reason "recent splash crash"
        $CacheBackups = @($CacheBackups | Where-Object { $_ })
    } else {
        Write-Step "No recent splash crash signature found; leaving client cache unchanged."
    }
} else {
    Write-Step "Skipped client cache reset by command-line switch."
}

Write-Step "Setting Oculus OpenXR runtime in HKCU and HKLM."
New-Item -Path "HKCU:\SOFTWARE\Khronos\OpenXR\1" -Force | Out-Null
New-ItemProperty -Path "HKCU:\SOFTWARE\Khronos\OpenXR\1" -Name ActiveRuntime -PropertyType String -Value $OculusRuntime -Force | Out-Null
& reg add "HKLM\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime /t REG_SZ /d $OculusRuntime /f | Out-Null

Write-Step "Setting Meta Horizon and Unity executables to high-performance GPU."
$GpuPrefPaths = @(
    "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences",
    "Registry::HKEY_USERS\S-1-5-18\Software\Microsoft\DirectX\UserGpuPreferences"
)
$Apps = @(
    "D:\Meta Horizon\Support\oculus-runtime\OVRServer_x64.exe",
    "D:\Meta Horizon\Support\oculus-runtime\OVRRedir.exe",
    "D:\Meta Horizon\Support\oculus-runtime\OVRServiceLauncher.exe",
    "D:\Meta Horizon\Support\oculus-client\OculusClient.exe",
    "D:\Meta Horizon\Support\oculus-client\Client.exe",
    "D:\Meta Horizon\Support\oculus-dash\dash\bin\OculusDash.exe",
    "D:\Meta Horizon\Support\oculus-platform-runtime\oculus-platform-runtime.exe",
    "D:\Meta Horizon\Support\oculus-remote-desktop\RemoteDesktopCompanion.exe",
    "D:\Unity\Editors\6000.3.0f1\Editor\Unity.exe"
)

$MetaHorizonSupportDir = "D:\Meta Horizon\Support"
if (Test-Path -LiteralPath $MetaHorizonSupportDir -PathType Container) {
    $Apps += Get-ChildItem -LiteralPath $MetaHorizonSupportDir -Recurse -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}

$Apps = @($Apps | Where-Object { $_ } | Sort-Object -Unique)
$GpuPreferenceSuccessCount = 0
foreach ($app in $Apps) {
    if (Test-Path -LiteralPath $app) {
        foreach ($gpuPrefPath in $GpuPrefPaths) {
            if (Set-GpuPreference -RegistryPath $gpuPrefPath -AppPath $app) {
                $GpuPreferenceSuccessCount++
            }
        }
    } else {
        Write-Step "Skipped missing executable: $app"
    }
}

Write-Step "Enabling Meta Horizon system proxy support."
& reg add "HKCU\Software\Oculus VR, LLC\Oculus" /v UseSystemProxy /t REG_DWORD /d 1 /f | Out-Null
& reg add "HKLM\Software\Oculus VR, LLC\Oculus" /v UseSystemProxy /t REG_DWORD /d 1 /f | Out-Null

$ProxyServer = ""
try {
    $internetSettings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    if ($internetSettings.ProxyEnable -eq 1 -and $internetSettings.ProxyServer) {
        $ProxyServer = [string]$internetSettings.ProxyServer
    }
} catch {}

if ($ProxyServer) {
    Write-Step "Mirroring current user proxy to WinHTTP: $ProxyServer"
    & netsh winhttp set proxy $ProxyServer | Out-Null
} else {
    Write-Step "No enabled user proxy detected; resetting WinHTTP proxy to direct."
    & netsh winhttp reset proxy | Out-Null
}

Write-Step "Removing stale offline Quest USB device records."
$StaleQuestDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -like "USB\VID_2833*" -and $_.Status -ne "OK"
}
foreach ($device in $StaleQuestDevices) {
    Write-Step "Removing stale device: $($device.FriendlyName) [$($device.InstanceId)]"
    & pnputil /remove-device "$($device.InstanceId)" | Out-Null
}

if (Test-Path -LiteralPath $OculusDriver) {
    Write-Step "Running Oculus driver repair."
    $driverProcess = Start-Process -FilePath $OculusDriver -PassThru
    if (-not $driverProcess.WaitForExit(60000)) {
        Write-Step "Oculus driver installer did not exit within 60 seconds; continuing."
    } else {
        Write-Step "Oculus driver installer exited with code $($driverProcess.ExitCode)."
    }
} else {
    Write-Step "Skipped Oculus driver repair; installer not found: $OculusDriver"
}

Write-Step "Starting Oculus runtime service."
try { Start-Service OVRService -ErrorAction SilentlyContinue } catch {}
Start-Sleep -Seconds 3

if (-not $SkipClientLaunch) {
    if (Test-Path -LiteralPath $OculusClient) {
        $launchTime = Get-Date
        if (Start-UserProcess -FilePath $OculusClient) {
            Start-Sleep -Seconds 20
            $newClientErrors = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA "Oculus") -Filter "OculusClientError-*.txt" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $launchTime } |
                Sort-Object LastWriteTime -Descending

            if ($newClientErrors) {
                $CrashAfterLaunch = $true
                $LatestCrashPath = $newClientErrors[0].FullName
                Write-Step "WARNING: Meta Horizon client wrote a crash log after launch: $LatestCrashPath"
            }
        }
    } else {
        Write-Step "Skipped Meta Horizon launch; client not found: $OculusClient"
    }
} else {
    Write-Step "Skipped Meta Horizon launch by command-line switch."
}

Write-Step "Running verification checks."
$OpenXrHkcu = (& reg query "HKCU\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime 2>&1) -join " "
$OpenXrHklm = (& reg query "HKLM\SOFTWARE\Khronos\OpenXR\1" /v ActiveRuntime 2>&1) -join " "
Write-Step "HKCU OpenXR: $OpenXrHkcu"
Write-Step "HKLM OpenXR: $OpenXrHklm"

$GraphOk = $false
try {
    $GraphOk = Test-NetConnection graph.oculus.com -Port 443 -InformationLevel Quiet
} catch {}
Write-Step "graph.oculus.com:443 reachable = $GraphOk"

$NvidiaLine = ""
try {
    $NvidiaLine = (nvidia-smi --query-gpu=name,display_active,encoder.stats.sessionCount --format=csv 2>&1) -join " | "
} catch {
    $NvidiaLine = "nvidia-smi failed: $($_.Exception.Message)"
}
Write-Step "NVIDIA status: $NvidiaLine"

$CompatibilitySummary = Get-LatestOculusCompatibilitySummary

$QuestDevices = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -like "USB\VID_2833*" -or $_.FriendlyName -match "Quest|Oculus|Reality Labs|Meta"
}
$QuestOkNames = @($QuestDevices | Where-Object {
    $_.Status -eq "OK" -and $_.FriendlyName -match "Highwind|XRSP|Commlib|ADB|Quest|Oculus"
} | Select-Object -ExpandProperty FriendlyName)

foreach ($device in $QuestDevices) {
    Write-Step "Device: $($device.Status) $($device.Class) $($device.FriendlyName) [$($device.InstanceId)]"
}

$EncoderActive = $false
if ($NvidiaLine -match ",\s*1(\D|$)" -or $NvidiaLine -match ",\s*[2-9]\d*(\D|$)") {
    $EncoderActive = $true
}

$CacheBackupText = "None"
if ($CacheBackups.Count -gt 0) {
    $CacheBackupText = ($CacheBackups -join [Environment]::NewLine)
}

$ClientCrashText = "No"
if ($CrashAfterLaunch) {
    $ClientCrashText = "Yes - see $LatestCrashPath"
}

$Message = @"
Meta Quest Link repair completed.

Network to graph.oculus.com: $GraphOk
NVIDIA encoder active: $EncoderActive
GPU preference entries written: $GpuPreferenceSuccessCount
Quest OK interfaces found: $($QuestOkNames.Count)
Meta Horizon client crash after launch: $ClientCrashText

Compatibility details:
$CompatibilitySummary

Client cache backups:
$CacheBackupText

If the headset is not connected yet, plug it in, allow USB/Quest Link in the headset, then run this shortcut again.

Log:
$LogPath
"@

Write-Step "Repair completed."

if (-not $NoMessageBox) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show($Message, "Meta Quest Link Fixer") | Out-Null
} else {
    Write-Step "Message box skipped by command-line switch."
}
