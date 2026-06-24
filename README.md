# Meta Quest Link GPU Fixer

Unofficial Windows repair tool for Meta Quest Link / Meta Horizon PC app cases where Quest Link does not appear to use the high-performance NVIDIA GPU, shows a misleading minimum-spec warning, or loses related OpenXR, USB driver, and proxy settings after an update.

This project is not affiliated with Meta. It exists to make one repeatable local fix easier to inspect, run, and improve.

## Who This Helps

Try this tool if you see one or more of these symptoms:

- Meta Quest Link says the PC does not meet minimum requirements even though an NVIDIA GPU is installed.
- Meta Quest Link / Oculus PC app appears to detect the wrong GPU or an integrated GPU.
- Windows Graphics Settings does not keep Meta Horizon / Oculus processes on high performance.
- Meta Quest Link is not the default OpenXR runtime.
- Quest Link USB interfaces are stale, missing, or left in a bad state after reconnecting the headset.
- Meta Horizon / Oculus PC app starts, crashes, or loses network/proxy settings after an update.

The tool focuses on local Windows configuration. It does not bypass Meta's official hardware compatibility checks.

## Tested Meta Quest Link Versions

Meta's PC app does not expose one stable version number in every location, so this project records the version files visible in the tested install.

Verified test environment:

- Meta Horizon / Meta Quest Link client component: `Support\oculus-client\version` = `32.1.1`
- Oculus USB driver component: `Support\oculus-drivers\version.txt` = `1.77.0.000001`
- Install layout: `Meta Horizon\Support\oculus-runtime`, `oculus-client`, and `oculus-drivers`
- Windows: Windows 11 build `26200`
- GPU target: NVIDIA systems, including hybrid-GPU laptops/desktops

Expected compatible app layouts:

- Newer Meta installs under `Meta Horizon`
- Older Oculus installs under `Oculus`
- Installs where `Support\oculus-runtime\oculus_openxr_64.json` and `Support\oculus-client\Client.exe` still exist

If Meta changes the internal folder layout or removes the bundled driver/runtime files, this script may need an update. Please open an issue with the newest log and your app version if that happens.

## What It Repairs

- Sets Meta Quest Link as the default OpenXR runtime in HKCU and HKLM, for both 64-bit and 32-bit registry views.
- Re-applies the OpenXR runtime after Oculus driver repair, because some driver operations can change runtime registration.
- Sets Windows high-performance GPU preferences for Meta Horizon / Oculus executables for both the current user and the LocalSystem account used by `OVRService`.
- Searches the Meta `Support` folder and applies GPU preference entries to bundled executables, not only a hardcoded app list.
- Enables the Oculus `UseSystemProxy` registry flag.
- Mirrors the current user proxy to WinHTTP when a user proxy is enabled, or resets WinHTTP proxy to direct when no user proxy is enabled.
- Removes stale offline Quest USB device records.
- Runs Oculus USB driver repair when the bundled driver installer is present.
- Restarts the Oculus runtime service.
- Resets recent Electron client cache state only when a known recent splash-screen crash signature is detected.
- Reports the latest Meta compatibility details from Oculus `PerfLog_*.json`, including CPU/GPU/OpenXR/USB status.

## Download And Run

1. Open the latest release or download this repository as a ZIP.
2. Extract the ZIP to any folder, for example `C:\Tools\meta-quest-link-gpu-fixer`.
3. Double-click `Run-MetaQuestLinkGpuFixer.cmd`.
4. Approve the Windows administrator prompt.
5. Read the final result dialog and save the log path if you need help.

You do not need to install PowerShell modules. Windows PowerShell 5.1 is enough.

## Expected Success Indicators

The final dialog and log should include useful checks such as:

- `OpenXR default runtime set: True`
- `graph.oculus.com:443 reachable = True`
- `NVIDIA encoder active: True` when Quest Link is actively streaming
- `Quest OK interfaces found` greater than zero when the headset is connected and allowed
- Compatibility details showing whether Meta sees the NVIDIA adapter

If `GPUCompat` contains `PASS` for the NVIDIA card but `overall_compat` is still `FAIL`, the blue minimum-spec banner may be caused by another Meta whitelist check, such as CPU or an enumerated integrated GPU. In that case, the warning banner does not necessarily mean Link is missing the NVIDIA GPU.

## Advanced Usage

Run from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-MetaQuestLink.ps1
```

Optional switches:

```powershell
# Do not reset Meta Horizon / Electron client cache.
.\Fix-MetaQuestLink.ps1 -SkipClientCacheReset

# Repair and verify without launching the Meta Horizon client.
.\Fix-MetaQuestLink.ps1 -SkipClientLaunch

# Write only to console/log and skip the final message box.
.\Fix-MetaQuestLink.ps1 -NoMessageBox

# Use this only if automatic install detection fails.
.\Fix-MetaQuestLink.ps1 -MetaInstallRoot "D:\Meta Horizon"
```

## Logs

Each run writes a UTF-8 log to:

```text
.\Logs\MetaQuestLinkFix-YYYYMMDD-HHMMSS-xxxx.log
```

Recent splash-crash cache backups are moved to:

```text
.\Logs\ClientCacheBackups\
```

Attach the newest log when opening an issue.

## Safety Notes

This tool intentionally changes Windows registry entries and device/service state related to Meta Quest Link. It does not edit your games, Unity projects, SteamVR files, or unrelated application settings.

Before running:

- Close VR apps and games.
- Disconnect or reconnect the headset only when the tool tells you to retry.
- Expect `OVRService` and Meta Horizon / Oculus processes to restart.

## What This Tool Cannot Fix

- Unsupported hardware according to Meta's current compatibility list.
- Bad USB cables, damaged ports, or headset-side permission denial.
- Broken Meta account login, server outages, or region/account restrictions.
- NVIDIA/Intel/AMD driver bugs that require a vendor driver update or rollback.
- Air Link network quality issues unrelated to local PC runtime registration.
- A future Meta PC app update that changes the internal `Support` folder layout.

## Good Issue Reports

Please include:

- Windows version
- Meta Horizon / Meta Quest Link app version, or the contents of `Support\oculus-client\version`
- Headset model
- GPU model and driver version
- Whether you are using USB Link or Air Link
- The newest `Logs\MetaQuestLinkFix-*.log`
- A screenshot of the warning, with private details hidden

## Repository Description

Suggested GitHub About description:

```text
Unofficial Windows repair tool for Meta Quest Link GPU detection, high-performance GPU preference, OpenXR runtime, USB driver, proxy, and compatibility warning issues.
```

Suggested topics:

```text
meta-quest, quest-link, gpu-fix, nvidia, openxr, vr, windows, powershell, usb-driver, troubleshooting
```

## License

MIT. See [LICENSE](LICENSE).
