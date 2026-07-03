# ClaudeTokenBar

ClaudeTokenBar is a native macOS menu bar app that shows live Claude Code token usage from `ccusage`.

## Requirements

- macOS 14 or newer
- Swift toolchain via Xcode
- `ccusage` on `PATH`, or `npx` so the app can run `npx -y ccusage@20`

## Build and Test

```sh
CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --disable-sandbox --manifest-cache local --cache-path .build/cache --config-path .build/config --security-path .build/security
CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --disable-sandbox --manifest-cache local --cache-path .build/cache --config-path .build/config --security-path .build/security
```

The local module cache and `--disable-sandbox` are only needed in restricted environments where SwiftPM cannot write its default cache or create its nested sandbox.

## Run

```sh
swift build -c release
cp .build/release/ClaudeTokenBar dist/ClaudeTokenBar.app/Contents/MacOS/
codesign --force --sign - dist/ClaudeTokenBar.app
open dist/ClaudeTokenBar.app
```

The app runs as an accessory `NSStatusItem` without a Dock icon. It invokes `ccusage` from the user home directory, never from this package directory. To start it at login, add `dist/ClaudeTokenBar.app` in System Settings → General → Login Items.

## Troubleshooting (macOS 26 Tahoe)

On Tahoe, menu bar items are hosted out-of-process by Control Center, and two
pitfalls apply:

- The status button must have an `image` (template SF Symbol). Title-only
  buttons can collapse to zero width in the remote hosting layer.
- On some machines Control Center fails to adopt items created after it
  started. If the paw icon is missing while the app is running, run
  `killall ControlCenter` — the menu bar rebuilds in a second and the item
  appears. Stale `"NSStatusItem Visible Item-N" = 0` keys in
  `com.apple.controlcenter` can also silently hide unnamed third-party items.

## Behavior

- Shows active block tokens and reset countdown in the menu bar.
- Keeps the last good snapshot if `ccusage` fails and marks the title with a warning.
- Refreshes on startup, menu open, wake from sleep, a 60-second safety timer, and project transcript changes.
- Stores the last snapshot under `~/Library/Application Support/ClaudeTokenBar/state.json`.
