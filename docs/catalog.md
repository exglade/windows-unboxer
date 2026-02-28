# Catalog Schema Guide

This guide explains `config/catalog.schema.json` and how to write your own `config/catalog.json`.

Use this when you want to customize what gets installed or executed.

## Purpose

`config/catalog.json` defines the deployment plan:

- app items (installed with winget)
- script items (run through the script runner)
- execution order via `priority`

## Top-Level Shape

```json
{
  "$schema": "./catalog.schema.json",
  "version": "1.0",
  "defaults": {
    "priority": 999
  },
  "items": []
}
```

| Field | Required | Type | Description |
| --- | --- | --- | --- |
| `$schema` | No | `string` | Recommended. Use `./catalog.schema.json` for editor validation. |
| `version` | Yes | `string` | Catalog schema version (current examples use `"1.0"`). |
| `defaults` | Yes | `object` | Global defaults for items. |
| `defaults.priority` | Yes | `integer >= 0` | Fallback priority when item priority is omitted. |
| `items` | Yes | `array` | List of app/script items. Must contain at least one item. |

## Item Contract (Common Fields)

Every item must include:

- `id` (format: `category.name`, regex `^[a-z0-9]+\.[a-z0-9]+$`)
- `type` (`app` or `script`)
- `category`
- `displayName`
- `requiresReboot` (`true`/`false`)

Optional common field:

- `priority` (`integer >= 0`) — lower values run first

## App Item (`type: "app"`)

App items must include `winget`:

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
    "scope": "machine",
    "override": null
  },
  "requiresReboot": false
}
```

`winget` fields:

| Field | Required | Type | Description |
| --- | --- | --- | --- |
| `id` | Yes | `string` | Winget package id. |
| `source` | Yes | `string` | Winget source name (usually `winget`). |
| `scope` | Yes | `"machine"` \| `"user"` | Install scope. |
| `override` | No | `string` \| `null` | Raw installer args passed to winget `--override`. |

## Script Item (`type: "script"`)

Script items must include `script`:

```json
{
  "id": "tweak.showExtensions",
  "type": "script",
  "category": "Tweaks",
  "displayName": "Show file extensions",
  "priority": 50,
  "script": {
    "path": "scripts/explorer-show-extensions.ps1",
    "parameters": {},
    "restartExplorer": true
  },
  "requiresReboot": false
}
```

`script` fields:

| Field | Required | Type | Description |
| --- | --- | --- | --- |
| `path` | Yes | `string` | Relative `.ps1` path from repo root. |
| `parameters` | No | `object` | Hashtable-like key/value parameters passed to script. |
| `restartExplorer` | No | `boolean` | Restart Explorer after script completes. Defaults to `false`. |

For script authoring contract (`-Parameters`, `-DryRun`), see [writing-scripts.md](writing-scripts.md).

## Writing Your Own Catalog

Suggested workflow:

1. Copy [catalog.json](../config/catalog.json) as a baseline.
2. Add or remove item entries.
3. Keep each `id` unique and in `category.name` format.
4. Set `priority` to control order (lower runs earlier).
5. Keep `requiresReboot` explicit on every item.
6. For script items, confirm script path exists and follows script contract.

## Validation Tips

- Add `"$schema": "./catalog.schema.json"` for editor validation/autocomplete.
- Keep profile overrides aligned with item IDs defined in your catalog.
- If you add script items, validate script behavior with `./tools/Test-Script.ps1`.
