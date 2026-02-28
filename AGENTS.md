# AGENTS.md

## Coding Conventions

- All `.ps1` files must be saved with **UTF-8 BOM** (the codebase uses box-drawing and arrow characters).

## Workflows

- Follow Conventional Commits, omit the scopes.
- `Invoke-ScriptAnalyzer` must report **zero** warnings.
  - `PSAvoidUsingWriteHost` is suppressed on CLI/TUI functions by design — this is an interactive console tool.
  - `PSUseShouldProcessForStateChangingFunctions` — add `SupportsShouldProcess` only for functions that change **system** state (e.g. kill processes, write registry). Suppress for in-memory-only functions like `New-Plan` / `New-State`.
  - Prefer removing unused parameters over suppressing `PSReviewUnusedParameter`.
- `.\tools\Run-Tests.ps1` must pass all Pester tests.
