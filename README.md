# Interactive Windows PC Setup with PowerShell

An interactive automated Windows PC setup with PowerShell.

Installs apps via **winget** and applies **registry tweaks** — using a keyboard-navigable terminal UI. Runs can be interrupted and resumed; a full report is shown at the end.

Feel free to fork this and modify the `catalog.json` for your own usage.

## Backstory

Every time I get a new Windows PC — or reset an existing one — I end up repeating the same ritual: reinstalling the applications I use and restoring the Windows settings I prefer.

It’s not difficult. It’s just repetitive.

There are bulk installer tools like Ninite that can speed things up. But most of them control the catalogue, the versions, and the package sources. They’re often a black box. Some even charge a fee. For something as fundamental as setting up my own machine, I want transparency and control.

Another option is automation via PowerShell with Chocolatey or Winget. I’ve done this before. In fact, I built a resilient Windows deployment script for my former company using Chocolatey and Boxstarter (see my other repository). It worked well for high-volume deployment.

However, over time I realized a few drawbacks:

- It required additional dependencies such as Chocolatey and Boxstarter.
- Boxstarter’s last release (v3.0.3) was October 6, 2023.
- It wasn’t flexible. A different machine profile meant writing a different script.

Today, Windows ships with Winget out of the box. It’s actively maintained, owned by Microsoft, and has a solid application catalogue. It works well without extra layers.

So I asked myself:
Why not simplify everything?
Why not remove the extra dependencies?
Why not build something lightweight, transparent, and tailored to how I actually use my PC?

That’s how this project was born.

## Project Principles

This project aims to be:

- **Transparent** - fully open-source, no hidden logic, no black boxes.
- **Lightweight** - minimal dependencies, built on what Windows already provides.
- **Customizable** - flexible enough to support different setups without rewriting the entire script.
- **Resilient** - supports tracking progress and resuming after interruptions.
- **Interactive** - not just automated, but engaging and user-driven when needed.
- **Simple** - no complicated setup process, just set up the basic and done.

At the end of the day, I just want to get the job done quickly, without giving up control over how it’s done.

**NOT an enterprise-grade Windows deployment tool.** It is designed for individual use and small-to-medium scale Windows PC setups.

---

## Prerequisites

- Windows 11 (build ≥ 22000)
- [winget](https://aka.ms/getwinget) (App Installer) — not required in `-DryRun` / `-Mock` mode

## Quick Start

1. Clone this repository.
2. Allow local scripts if you haven't already:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```
3. Run `Setup.ps1`:
   ```powershell
   .\Setup.ps1
   ```

Use `↑`/`↓` to navigate, `Space` to toggle items, `Enter` to confirm.

## Usage

| Flag | Description |
|---|---|
| _(none)_ | Normal interactive run |
| `-DryRun` | Log commands without executing anything |
| `-Mock` | Fake execution — useful for testing state and resume logic |
| `-TweakTarget Test` | Redirect registry writes to a safe test key (use with `-Mock`) |
| `-FailStepId <id>` | Simulate a failure on a specific step ID (use with `-Mock`) |

```powershell
.\Setup.ps1 -DryRun
.\Setup.ps1 -Mock -TweakTarget Test
.\Setup.ps1 -Mock -FailStepId dev.vscode
```

If a run is interrupted, re-running `Setup.ps1` detects the saved state and offers to **resume pending steps**, **re-run failed steps**, **start over**, or **view the last report**.

## Profiles

Pass a profile JSON file with `-ProfilePath` to pre-select items and override per-app winget settings without editing `catalog.json`:

```powershell
.\Setup.ps1 -ProfilePath .\profile.example.json
```

Copy `profile.example.json` as a starting point and adjust to your needs. Both fields are optional:

```json
{
  "$schema": "./profile.schema.json",
  "selectedIds": ["core.chrome", "dev.vscode", "dev.git"],
  "overrides": {
    "dev.vscode": { "scope": "user", "override": "/SILENT /MERGETASKS=!runcode" },
    "core.chrome": { "scope": "user" }
  }
}
```

| Field | Description |
|---|---|
| `selectedIds` | Items pre-checked in the TUI. Replaces the default category-based selection. The user can still toggle items before confirming. |
| `overrides` | Per-app winget overrides keyed by item ID. Only `scope` and `override` can be changed; `id` and `source` are fixed. Silently ignored for `tweak` items. |

## Catalog

Items are defined in `catalog.json`. There are two types:

**App** — installed via winget:
```json
{
  "id": "dev.vscode",
  "type": "app",
  "category": "Dev",
  "displayName": "VS Code",
  "priority": 300,
  "winget": {
    "id": "Microsoft.VisualStudioCode",
    "source": "winget",
    "scope": "machine"
  }
}
```

**Tweak** — registry write:
```json
{
  "id": "tweak.showExtensions",
  "type": "tweak",
  "category": "Tweaks",
  "displayName": "Show file extensions",
  "priority": 50,
  "tweak": {
    "kind": "registry",
    "actions": [
      { "path": "HKCU:\\...", "name": "HideFileExt", "type": "DWord", "value": 0 }
    ],
    "restartExplorer": true
  }
}
```

Items in the `Core`, `Dev`, and `Tweaks` categories are pre-checked by default. Lower `priority` values run first.

## Project Structure

```text
Setup.ps1            # Entry point and orchestrator
catalog.json         # App and tweak definitions
modules/
  Catalog.ps1        # Load and query catalog.json
  Common.ps1         # Logging, JSON I/O, prerequisite checks
  Executor.ps1       # Run plan steps (winget installs, tweak dispatching)
  PlanState.ps1      # Build plan/state, resume menu, report
  TuiChecklist.ps1   # Interactive terminal checklist UI
  Tweaks.ps1         # Registry tweak application
setup-artifacts/     # Logs, plan.json, state.json (generated at runtime)
tests/               # Pester unit tests
```

## Testing

Requires [Pester](https://pester.dev) v5+.

```powershell
.\Run-Tests.ps1
```

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
