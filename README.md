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
.build/debug/ClaudeTokenBar
```

The app runs as an accessory `NSStatusItem` without a Dock icon. It invokes `ccusage` from the user home directory, never from this package directory.

## Behavior

- Shows active block tokens and reset countdown in the menu bar.
- Keeps the last good snapshot if `ccusage` fails and marks the title with a warning.
- Refreshes on startup, menu open, wake from sleep, a 60-second safety timer, and project transcript changes.
- Stores the last snapshot under `~/Library/Application Support/ClaudeTokenBar/state.json`.
