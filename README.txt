Meta Quest Link Fixer

Double-click the desktop shortcut named "Meta Quest Link Fixer".
The tool requests administrator permission, repairs common Meta Horizon update regressions, and writes logs to:

D:\MetaQuestLinkFixer\Logs

It repairs:
- Oculus OpenXR runtime in HKCU and HKLM
- Windows high-performance GPU preferences for Meta Horizon and Unity, for both
  the current user and the LocalSystem account used by OVRService
- Oculus UseSystemProxy registry flag
- WinHTTP proxy mirroring when a user proxy is enabled
- stale offline Quest USB device records
- Oculus USB driver reinstall/repair
- Oculus runtime service restart
- recent Meta Horizon splash-crash cache state by backing up the Electron client
  cache under Logs\ClientCacheBackups before rebuilding it

It also avoids writing the same log file through PowerShell transcript and manual
logging at the same time, which prevents the "file is being used by another
process" Add-Content error.

Success indicators:
- graph.oculus.com:443 reachable = True
- Reality Labs Highwind/XRSP/Commlib interfaces = OK when the headset is connected
- nvidia-smi encoder.stats.sessionCount > 0 when Quest Link is active
- Compatibility details show whether Meta is seeing the NVIDIA GPU. If NVIDIA is
  PASS but overall_compat is FAIL, the blue minimum-spec banner is usually caused
  by another Meta whitelist check such as CPU or an enumerated integrated GPU,
  not by Quest Link missing the RTX GPU.

Advanced switches:
- -SkipClientCacheReset leaves the Meta Horizon client cache untouched
- -SkipClientLaunch repairs and verifies without launching Meta Horizon
- -NoMessageBox writes the result only to the console/log
