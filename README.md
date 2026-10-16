# LightSnap

A small, fast area-screenshot tool for the macOS menu bar. Press a hotkey, drag over part of the screen, scribble on it, then copy or save. That's it.

- **⌘⇧9** freezes the screen and lets you select an area (works across multiple displays)
- Move and resize the selection with its handles; **⌘A** selects the whole screen
- Annotate: pen, line, arrow, rectangle, ellipse, highlighter, text, 8 colors, undo
- Copy, save (PNG/JPEG), print, or share — at full Retina resolution
- No network access, no accounts, no tracking. Screenshots never leave your Mac unless you share them.

Requires macOS 14 (Sonoma) or later, Apple Silicon or Intel.

## Install

1. Download `LightSnap.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag **LightSnap.app** into your **Applications** folder.
3. Open it. macOS will say it *"could not verify LightSnap"* — this is because the app is not
   signed with a paid Apple Developer ID. Click **Done**, then go to
   **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to LightSnap.
4. When asked, allow **Screen & System Audio Recording** for LightSnap, then quit and reopen it.

A camera icon appears in the menu bar. Press **⌘⇧9** to take a screenshot.

> **Only download LightSnap from this repository's Releases page.** Every release is built
> by GitHub Actions directly from the source in this repo, and ships with a SHA-256 checksum.
> To check your download: `shasum -a 256 LightSnap.zip` should match `LightSnap.zip.sha256`.

## Keyboard shortcuts (while capturing)

| Key | Action |
|---|---|
| Drag | Select area |
| ⌘A | Select whole screen |
| ⌘Z | Undo last annotation |
| ⌘C / Return | Copy to clipboard |
| ⌘S | Save to file |
| ⌘P | Print |
| Esc / right-click | Cancel |

## Build from source

Needs the Xcode command-line tools (`xcode-select --install`).

```bash
./build.sh            # builds build/LightSnap.app
./build.sh --install  # also copies it to /Applications and launches it
```

Each local build gets a new ad-hoc signature, so macOS may ask for Screen Recording permission again after rebuilding.

## Releasing

Push a version tag; GitHub Actions builds the universal app and publishes the release:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

## Privacy & permissions

- **Screen Recording** is used only at the moment you press the hotkey or choose *Take Screenshot*.
- The hotkey uses the system hotkey API, so no Accessibility permission is needed.
- The app contains no networking code. Files are written only where you choose to save them,
  plus a temporary copy when you use *Share* (deleted on the next share or app launch).

## License

MIT — see [LICENSE](LICENSE).
