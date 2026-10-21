# Native macOS Steam + Wine mode — feasibility (from NotProton, GPL-3)

Source studied: `upstream/notproton` (shallow clone). Paths below are relative to it.

## How NotProton does it
- **Enabling Steam Play on macOS Steam:** Steam's compat-tool code exists on macOS but is inactive.
  - NotProton injects an arm64 Dobby hook dylib via `LSEnvironment.DYLD_INSERT_LIBRARIES` in `Steam.app/Contents/Info.plist`, then ad-hoc re-signs Steam (`app/.../SteamInstaller.swift:159-172`).
  - Hooks are located with byte signatures per Steam build (`signatures/macos.arm64/<build>.json`, only 3 builds).
  - They force `CCompatManager` on (`dylib/hooks/hook_compat.c`, `dylib/feats/compat.c`).
  - A Steam self-update can undo the injection.
- **Compat tool:** `compatibilitytools.d/notproton*/{compatibilitytool.vdf,toolmanifest.vdf,run}`; `run` = `dylib/feats/compat_run.sh` (1,652 lines).
  - It handles the Steam verbs.
  - It keeps one prefix per game at `steamapps/compatdata/<appid>/pfx`, cloned from a template.
- **Steam API bridge:** Proton's `lsteamclient` (PE + Mach-O `.so`) dlopens the native `steamclient.dylib`, which is fat x86_64+arm64.
  - `steamclient64.dll` exports are redirected to `lsteamclient.dll` by binary-patching CrossOver's ntdll.
  - Valve's Windows DLLs are downloaded at runtime from Valve's CDN with pinned hashes.
- **Windows depots:** chosen by Steam itself once an app maps to a tool with `from_oslist=windows`. There is no `@sSteamCmdForcePlatformType`.

## Licensing
- `lsteamclient` is under the **Steamworks SDK License**, which is not GPL-compatible. It cannot be merged into barrel; at most it can be built and shipped as a separate artifact.
- `steam-shim` (Proton `steam_helper`) is BSD-3, which is fine.
- Valve's DLLs are proprietary: download them only, never redistribute them.

## Decision (2026-10-21)
We are deferring this mode. The current mode (Windows Steam inside a barrel bottle) already runs Stonewards. On the menu benchmark its GPU time per frame matches CrossOver/D3DMetal (`odd/tasks/engine-cli-graphics.md` L29), so the mode's main motivation, performance, is not supported by evidence.

The native mode has three costs:
- It requires patching and re-signing the user's Steam.app.
- It requires per-Steam-build hook signatures.
- It requires a component under a non-GPL licence.

It would be revisited only for features that the in-Wine client lacks, such as Mac-native overlay or input.

The cheap first experiment, if it is ever revisited: write only `compatibilitytools.d/barrel/` with `from_oslist windows`, `to_oslist macos` and check whether unmodified macOS Steam lists it. NotProton's hooks suggest it will not.
