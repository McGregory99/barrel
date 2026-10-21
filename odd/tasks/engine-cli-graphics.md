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
| T1 | S1 | inline | done | Wine `wine-11.0-2-gb4af2ac` (CX patches `b616515` + build fix `b4af2ac`) built and installed to `build/install`; `scripts/build-engine.sh` |
| T2 | S1 | inline | done | `barrel create Smoke --template win10` → real prefix, reports Windows 10 build 19045; 64-bit cmd.exe → AMD64, 32-bit (WoW64) cmd.exe → x86; winecfg ran 10 s, 2 expected errors only |
| T3 | S1 | inline | pending | gnutls + GStreamer x86_64 deps |
| T4 | S2 | inline | done | `barrel` Swift package: create/list/info/copy/delete/default/templates — commit `6adcccf`, 13 tests |
| T5 | S2 | inline | partial | export/restore/run done — commit `3c7d775`, 22 tests total; macOS launchers (F4) pending until Wine runs |
| T6 | S3 | inline | in progress | selector `barrel graphics` + `msync` (`7162ba4`, 32 tests); D3D11 smoke test `tools/d3d11-smoke`: wined3d OK (120 frames, FL 10.1, MSync up); DXVK built (`a7030e8`), awaiting Vulkan rebuild; DXMT build + D3DMetal (user GPTK) pending |

## Log
- L1 (2026-10-21): "ponte con las fases 3,4,5"
- L2: Host is arm64 macOS 26.5.1; Wine must be x86_64 under Rosetta. Homebrew is arm64, so x86_64 deps are built from the CrossOver source tarball into `build/deps` (no second Homebrew). bison 3.8.2 installed via Homebrew (system bison 2.3 too old).
- L3: freetype top-level configure needs the `dlg` submodule; built with CMake instead.
- L4: Wine configure: `--enable-archs=i386,x86_64`, missing gnutls, GStreamer, MoltenVK, FFmpeg (deferred to T3/T6). Build running.
- L5: CLI named `barrel` (working name). Bottles are always 64-bit WoW64; `_64` template suffix only selects the version. Smoke-tested against a fake wine; real Wine smoke test waits on T1.
- L6: Build failed in `dlls/win32u/vulkan.c`: CX HACK 25909 dropped the `#ifdef SONAME_LIBVULKAN` guard, so builds without Vulkan break. Fixed in our Wine branch (`b4af2ac`), keeping the `CX_LIBVULKAN` override. Build resumed.
- L7 (T6 license): D3DMetal (GPTK 3.0 in CrossOver) license reportedly grants use only to develop/test/evaluate games; redistribution is unclear (Apple forum thread 841547 asks Apple to clarify). Decision: do NOT bundle D3DMetal; the user points `barrel` at their own GPTK install downloaded from Apple. DXVK (zlib), DXMT and MoltenVK (Apache-2.0) can be bundled.
- L8: Real-Wine smoke test passed (see T2). Wine needs `WINEDLLOVERRIDES=mscoree,mshtml=` during init until Mono/Gecko are provided, otherwise wineboot prompts for an installer.
- L9: DXVK 1.10.3 does not build with mingw-w64 14 / GCC 16: fixed with `-include cstdint`, the upstream namespaced `D3DDEVINFO_RESOURCEMANAGER`, and a feature-detected guard for the `ID3D10StateBlock` UUID.
- L10: MSync verified at runtime ("msync: up and running"). D3D11 smoke test passes on wined3d.
- L11: Wine rebuilt with MoltenVK (`SONAME_LIBVULKAN libMoltenVK.dylib`). DXVK 1.10.3 loads and enumerates "Apple M2" via MoltenVK, but every feature level fails with "Missing feature: geometryShader" → `D3D11CreateDeviceAndSwapChain` hr=0x80070057. Upstream MoltenVK lacks geometry shaders; CodeWeavers' MoltenVK sets `_features.geometryShader = true` ("Required by DXVK for D3D10", MVKDevice.mm:2491) with GS emulation. Next: build CX MoltenVK (`upstream/moltenvk-cx`, running).
- L12: Known issue: through `barrel run` (`wine start /wait`) the failing DXVK run did not return for >3 min, while a direct `wine` run exited with code 1. Investigate (likely a crash/error dialog waiting for input).
- L13: L12 hang not reproduced: the same `barrel run` with DXVK returned exit 1 in <60 s. The first run started right after `make install`; kept as watch item.
