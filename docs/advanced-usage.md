# Advanced Usage

This page helps you choose the right guide for advanced customization and testing.

If you only want a normal setup run, follow [README.md](../README.md) and use `./Start.ps1`.

## Use Cases and Where to Go

### 1. Customize app and script list

Use a custom `config/catalog.json` when you want to control which apps and scripts are deployed.

- Add/remove app items
- Add/remove script items
- Adjust execution order with `priority`

Go to: [catalog.md](catalog.md)

### 2. Write custom scripts (tweaks, pre-/post-install workflow)

Use custom scripts when you need extra setup logic, such as:

- Windows tweaks
- pre-install preparation
- post-install configuration

Author script contract and behavior: [writing-scripts.md](writing-scripts.md)  
Add script into catalog: [catalog.md](catalog.md)

### 3. Create deployment presets with profiles

Use profiles when you want different presets for different machines (for example: work laptop vs personal PC).

- Select a predefined subset of catalog items
- Override app scope/arguments or script parameters per item

How to run profiles: [README.md](../README.md#quick-start)  
How to write profile files: [profile.md](profile.md)

### 4. Development testing with `-Mock` and `-FailStepId`

Use testing flags when validating plan/state behavior, failure handling, and resume flow:

```powershell
.\Start.ps1 -Mock
.\Start.ps1 -Mock -FailStepId dev.vscode
```

- `-Mock` simulates execution without making system changes.
- `-FailStepId <id>` injects a failure for one step ID to test error/resume behavior.
- `-FailStepId` only applies when `-Mock` is enabled.
