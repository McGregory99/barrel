# BarrelApp

Native SwiftUI front-end over `BarrelCore`, Steam first:

- **Library** (the start screen): "Install Steam" on first run; then the games Steam has installed, each
  with Play (applies its game profile, see `../docs/profiles.md`), its graphics backend (DXVK, DXMT,
  wined3d) and "Add to Dock", which creates a Mac app for the game in `~/Applications/Barrel`.
- **Advanced** (sidebar): bottles. Create, copy, delete, export and restore them, install software
  from recipes, choose the default bottle, graphics backend and MSync, and run programs or documents
  (file picker or drag and drop).

## Build and run

Requires macOS 14+ and a Wine build (x86_64, via Rosetta).

```sh
cd app
swift build
swift run BarrelApp
swift test
```

Sparkle updates are deferred until there is a signed app bundle.

## Settings

Open **Barrel > Settings** (Cmd+,). Values are stored in UserDefaults. When a value has never been saved, the
same environment variables the CLI uses seed it:

| Setting | Env var | Default |
|---|---|---|
| Wine binary | `BARREL_WINE` | `wine` found in `PATH` |
| Data directory | `BARREL_HOME` | `~/Library/Application Support/Barrel` |
| Native libraries | `BARREL_LIBS` | none |
| DXVK | `BARREL_DXVK` | none (backend disabled) |
| DXMT | `BARREL_DXMT` | none (backend disabled) |
| Game Porting Toolkit | `BARREL_GPTK` | none (backend disabled) |
| Game profiles (not shown in Settings) | `BARREL_PROFILES` | Barrel.app's `Resources/profiles`; `<data>/Profiles` is always read first |

Press **Apply** to reload the bottle list with the new paths.

## Architecture

- `BarrelAppKit` (testable): `BottleGateway` port with a `BarrelCoreGateway` adapter, `BottleListViewModel`
  (container, runs every Wine call off the main actor), `AppSettings`/`SettingsStore`, `AppController`.
- `BarrelApp`: presentational SwiftUI views that receive state and closures.
- The package uses Swift 5 language mode because `BarrelCore` service types are not `Sendable`.
