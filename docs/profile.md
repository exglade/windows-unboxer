# Profile Guide

This guide explains `config/profile.schema.json` and how to write your own profile file.

For run commands and when to use profiles, see [README.md](../README.md#profiles).

## Purpose

A profile file lets you:

- pre-select catalog items with `selectedIds`
- override app/script settings per item with `overrides`

Use profiles when you want reusable presets for different machine types.

## File Shape

```json
{
  "$schema": "./profile.schema.json",
  "selectedIds": ["dev.vscode", "dev.git"],
  "overrides": {
    "dev.vscode": {
      "scope": "user",
      "override": "/SILENT /MERGETASKS=!runcode"
    },
    "tweak.showExtensions": {
      "parameters": {
        "example": true
      }
    }
  }
}
```

## Top-Level Fields

| Field | Required | Type | Notes |
| --- | --- | --- | --- |
| `$schema` | No | `string` | Recommended. Use `./profile.schema.json` for editor validation. |
| `selectedIds` | No | `string[]` | IDs in `category.name` format (for example `dev.vscode`). |
| `overrides` | No | `object` | Keys are item IDs; values are per-item override objects. |

## `selectedIds`

- Item IDs must match `^[a-z0-9]+\.[a-z0-9]+$`.
- In interactive mode, these IDs are pre-checked in the main menu.
- In `-Silent` mode, these IDs are used directly (no menu prompt).
- If omitted, no profile-driven pre-checks are applied.

## `overrides`

Each key under `overrides` is an item ID from `config/catalog.json`.

Supported override fields:

| Field | Applies To | Type | Description |
| --- | --- | --- | --- |
| `scope` | App item | `"machine"` \| `"user"` | Overrides winget install scope. |
| `override` | App item | `string` \| `null` | Raw argument string passed to winget `--override`. |
| `parameters` | Script item | `object` | Script parameter override object (merged with catalog defaults). |

Rules:

- Override objects cannot contain unknown fields.
- Each override object must contain at least one field.
- Use app fields only for app items; use `parameters` for script items.

## Common Patterns

### 1. Work laptop profile

```json
{
  "$schema": "./profile.schema.json",
  "selectedIds": ["core.chrome", "dev.vscode", "dev.git"],
  "overrides": {
    "dev.vscode": { "scope": "user" }
  }
}
```

### 2. Personal machine profile

```json
{
  "$schema": "./profile.schema.json",
  "selectedIds": ["core.chrome", "media.spotify", "comm.discord"]
}
```

### 3. Script parameter override

```json
{
  "$schema": "./profile.schema.json",
  "overrides": {
    "dev.nerdfont": {
      "parameters": {
        "fontName": "CascadiaCode"
      }
    }
  }
}
```

## Validation Tips

- Start from [profile.example.json](../config/profile.example.json).
- Keep IDs in sync with [catalog.json](../config/catalog.json).
- Add `"$schema": "./profile.schema.json"` to get editor autocompletion and validation.
