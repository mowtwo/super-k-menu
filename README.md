# SuperKMenu

SuperKMenu is a small macOS menu bar app plus Finder Sync extension for configurable Finder context menu actions.

It lets you add commands such as "Open in VS Code" or "Open in Terminal" to Finder's right-click menu. Actions run in the background through `/bin/zsh -lc`; the configuration window only appears when you launch the app directly or open it from the menu bar.

## Origin

SuperKMenu started from a small frustration raised by K, a real friend from a WeChat group: the existing "super right-click" style tools were not flexible enough for quickly wiring up launch actions such as opening the current Finder folder in WezTerm.

The name is a nod to that friend K and to the idea of a keyboard-like, configurable Finder menu: a small "super key" for launching the actions you actually use.

The goal is to keep that workflow direct: define a command, give it a menu title, enable it, and use it from Finder without building Automator services or digging through nested Services menus.

## Features

- Configurable Finder context menu actions
- JSON-backed config at `~/.super-k-menu/actions.json`
- Disabled example actions for VS Code and Terminal
- Menu bar controls for opening settings and restarting Finder
- Finder menu action icons inferred from the target app, with optional overrides
- Customizable status bar icon through `statusBarIconPath`
- Finder extension config mirroring for reliable sandboxed reads

## Install

Download the latest unsigned zip from the GitHub Releases page, unzip it, and move `SuperKMenu.app` to `/Applications`.

Because this build is unsigned, macOS may block the first launch. Use right-click `Open` on `SuperKMenu.app` for the first launch if needed.

Then:

1. Launch `SuperKMenu.app`.
2. Enable `SuperKMenuFinderExtension` in System Settings if macOS has not enabled it automatically.
3. Enable the actions you want in SuperKMenu.
4. Restart Finder from the menu bar app.

Launching SuperKMenu registers and enables its Finder extension. Quitting SuperKMenu disables/unregisters the Finder extension and restarts Finder, so SuperKMenu menu items are removed from Finder's context menu after the app exits.

## Configuration

User-editable configuration lives at:

```text
~/.super-k-menu/actions.json
```

The app mirrors this file into the Finder extension container so the sandboxed extension can read the same configuration reliably.

The top-level JSON has:

- `actions`: Finder menu actions
- `allowedFolders`: folders tracked by the app
- `statusBarIconPath`: optional path to a custom menu bar icon image

Each action supports:

- `id`: stable action identifier
- `title`: text shown in Finder's context menu
- `command`: shell command run through `/bin/zsh -lc`
- `enabled`: whether the action appears in Finder
- `iconPath`: optional icon override. Use `sf:<symbol-name>` for a simple SF Symbol, or a local file path for a custom image/app icon.

Use `{path}` in a command to receive the current Finder folder path. If a file is selected, SuperKMenu passes the selected file's parent folder.

Example:

```json
{
  "actions": [
    {
      "id": "example-vscode",
      "title": "Open in VS Code",
      "command": "open -a \"Visual Studio Code\" {path}",
      "enabled": false
    },
    {
      "id": "example-terminal",
      "title": "Open in Terminal",
      "command": "open -a Terminal {path}",
      "enabled": false
    }
  ],
  "allowedFolders": [],
  "statusBarIconPath": null
}
```

`iconPath` is optional. If it is empty, SuperKMenu tries to infer the target app from the command or title and uses that app's icon. If no target app can be found, it falls back to a compact symbol.

## Build

```bash
./Scripts/package-app.sh
```

The packaged app is written to:

```text
dist/SuperKMenu.app
```

## Release

Releases are built by GitHub Actions when a `v*` tag is pushed:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds an unsigned macOS app and uploads `SuperKMenu-<tag>-unsigned.zip` to the GitHub release.

## License

MIT
