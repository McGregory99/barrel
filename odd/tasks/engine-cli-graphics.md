# Engine, bottle CLI and graphics backends (phases 3–5)
Objective: open reimplementation of CrossOver's engine layer on macOS (Apple Silicon via Rosetta).
Branch: `feat/engine-cli-graphics` · Delivery: ask-on-risk · Test runner: Swift Testing (`swift test`) for the CLI; smoke runs for Wine.

## Specs
- S1 (phase 3 — engine): "Compilar el Wine de CrossOver 26.3 tal cual, como referencia que sabemos que funciona." / "Partir los parches por áreas y aplicarlos sobre Wine 11.0 oficial, empezando por MSync, la conexión con D3DMetal y el driver de Mac." Acceptance: "`winecfg` y un `.exe` de prueba arrancan dentro de una bottle."
- S2 (phase 4 — bottle CLI): "Crear, copiar, borrar y exportar/importar bottles, más la plantilla de versión de Windows (F1 y F2)." / "Lanzar programas y documentos, y crear accesos directos en macOS (F3 y F4)." Acceptance: "los mismos casos de uso que `cxbottle` y `cxstart`, con tests." Clean-room: behavior from `--help` only, no CodeWeavers code.
- S3 (phase 5 — graphics): "Integrar DXVK con MoltenVK, DXMT y D3DMetal, con un selector en cada bottle (F6)." / "Revisar la licencia de redistribución de D3DMetal." Acceptance: "un juego D3D11 funciona con cada motor."
- Assumption: CLI written in Swift (shares code with the future SwiftUI GUI). Open to change.

## Tasks
| ID | Specs | Route | Status | Evidence |
|---|---|---|---|---|
| T1 | S1 | inline | in progress | wine-11.0 + CX patch commit `b616515` (upstream clone, branch `cx-26.3`); x86_64 freetype built; configure OK |
| T2 | S1 | inline | pending | smoke test: wineboot + winecfg + test .exe |
| T3 | S1 | inline | pending | gnutls + GStreamer x86_64 deps |
| T4 | S2 | inline | done | `barrel` Swift package: create/list/info/copy/delete/default/templates — commit `6adcccf`, 13 tests |
| T5 | S2 | inline | partial | export/restore/run done — commit `3c7d775`, 22 tests total; macOS launchers (F4) pending until Wine runs |
| T6 | S3 | inline | pending | MoltenVK + DXVK, DXMT, D3DMetal selector per bottle; license check |

## Log
- L1 (2026-10-21): "ponte con las fases 3,4,5"
- L2: Host is arm64 macOS 26.5.1; Wine must be x86_64 under Rosetta. Homebrew is arm64, so x86_64 deps are built from the CrossOver source tarball into `build/deps` (no second Homebrew). bison 3.8.2 installed via Homebrew (system bison 2.3 too old).
- L3: freetype top-level configure needs the `dlg` submodule; built with CMake instead.
- L4: Wine configure: `--enable-archs=i386,x86_64`, missing gnutls, GStreamer, MoltenVK, FFmpeg (deferred to T3/T6). Build running.
- L5: CLI named `barrel` (working name). Bottles are always 64-bit WoW64; `_64` template suffix only selects the version. Smoke-tested against a fake wine; real Wine smoke test waits on T1.
