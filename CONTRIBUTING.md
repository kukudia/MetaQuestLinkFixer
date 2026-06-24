# Contributing

Thanks for helping make Meta Quest Link GPU Fixer useful beyond one machine.

## Good Issues Include

- Windows version
- Meta Horizon / Meta Quest Link app version if known
- Headset model
- GPU model and driver version
- Whether the headset is connected by USB Link, Air Link, or not connected
- The newest log from `Logs`
- Screenshots of warnings, with private details hidden

## Development Notes

- Keep the tool dependency-free: Windows PowerShell 5.1 should be enough.
- Preserve CRLF line endings for `.ps1`, `.cmd`, `.txt`, and `.md` files.
- Avoid hardcoded local install paths unless they are only examples in docs.
- Do not include user logs, cache backups, tokens, or machine-specific files in commits.
- Keep repairs targeted to Meta Quest Link GPU detection, OpenXR, USB driver, proxy, and related PC app state.

## Validation

Before opening a PR, run:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\Fix-MetaQuestLink.ps1), [ref]$tokens, [ref]$errors) | Out-Null
$errors
git diff --check
```
