# Windows Unboxer

An interactive automated Windows PC setup with PowerShell.

Installs apps via **winget** and runs **PowerShell scripts** for configuration — using a keyboard-navigable terminal UI. Runs can be interrupted and resumed; a full report is shown at the end.

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
- [winget](https://aka.ms/getwinget) (App Installer)

## Quick Start

1. Clone this repository.
2. Allow local scripts if you haven't already:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

3. Run `Start.ps1`:

   ```powershell
   .\Start.ps1
   ```

Use `↑`/`↓` to navigate, `Space` to toggle items, `Enter` to confirm.

### Parameters

| Flag | Description |
| --- | --- |
| _(none)_ | Normal interactive run |
| `-DryRun` | Log commands without executing anything |
| `-ProfilePath <path>` | Load a profile JSON file to pre-select items and apply overrides. |
| `-Silent` | Skip all prompts — runs fully unattended using catalog defaults or a profile |

**Examples:**

```powershell
.\Start.ps1
.\Start.ps1 -Silent
.\Start.ps1 -Silent -ProfilePath .\profile.example.json
.\Start.ps1 -DryRun
```

All catalog items are pre-checked by default. When `-ProfilePath` is used, preselection comes from profile `selectedIds` (or none if omitted). Lower `priority` values in `catalog.json` run first.

If a run is interrupted, re-running `Start.ps1` detects the saved state and offers to **resume pending steps**, **re-run failed steps**, **start over**, or **view the last report**.

See [advanced-usage.md](/docs/advanced-usage.md) for instructions on more ways to use this tool.

## Project Structure

```text
Start.ps1            # Entry point and orchestrator
Test-Script.ps1      # Script validator (test your scripts)
catalog.json         # App and script definitions
modules/
  Catalog.ps1        # Load and query catalog.json
  Common.ps1         # Logging, JSON I/O, prerequisite checks, Explorer helpers
  Executor.ps1       # Run plan steps (winget installs, script dispatching)
  PlanState.ps1      # Build plan/state, resume menu, report
  ScriptRunner.ps1   # PowerShell script runner
  MainMenu.ps1       # Interactive main menu terminal UI
docs/
   advanced-usage.md  # Advanced scenarios and testing flags
   profile-schema.md  # Profile schema reference and authoring guide
   catalog-schema.md  # Catalog schema reference and authoring guide
   writing-scripts.md # Script runner contract and script authoring guide
scripts/             # PowerShell scripts for catalog script items
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
