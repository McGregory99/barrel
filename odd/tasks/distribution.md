# Distribution (phase 9)
Objective: ship barrel as a self-contained, license-compliant macOS app. Signing and notarization come last.
Branch: `feat/engine-cli-graphics` · Delivery: ask-on-risk · Test runner: Swift Testing (`swift test`) plus scripted bundle checks.

## Specs
- S1 (phase 9, quoted from the plan shown to the user): "Firma y notarización, cumplimiento de la LGPL (publicar tus parches) y los avisos de licencia de cada componente."
- S2 (licensing, L27): project license "GPL-3.0" ("si, GPL-3 me vale").
- Assumption: notarization needs the user's Apple Developer ID. Until it is available, bundles are ad-hoc signed and the notarization step is scripted but not run.
- Assumption: a self-contained `Barrel.app` (app + `barrel` CLI + Wine runtime) is in scope, because signing needs a bundle. GUI launchers (deferred in L31 of engine-cli-graphics) depend on it.
- Out of scope: redistributing D3DMetal/GPTK (Apple license, see engine-cli-graphics L7), Valve DLLs, and CrossOver's own binaries.

## Tasks
| ID | Specs | Route | Status | Evidence |
|---|---|---|---|---|
| T1 | S1, S2 | inline | done `53e847a` | LGPL: our patches exported as files under `patches/`; `THIRD_PARTY_NOTICES.md` with each component's license and source |
| T2 | S1 | inline | done | relocatable runtime: Wine + deps + DXVK + DXMT with `@loader_path`/`@rpath` links, no absolute `build/` paths |
| T3 | S1 | inline | pending | `scripts/package-app.sh` builds `Barrel.app` (BarrelApp + barrel CLI + runtime); the app defaults to the bundled runtime |
| T4 | S1 | inline | pending | signing: ad-hoc now; Developer ID + `notarytool` script ready, blocked on the user's certificate |

## Log
- L1: 2026-10-22, user: "si, reábrelo sin el contador, deja de hacerme tntas preguntas, te autorizo para lo que quieras. simplemente ponte a trabajar y no me preguntes todo el rato. Hay un plan, siguelo". Phase 9 follows phases 3–7 in that plan.
- L2: T2. `scripts/package-runtime.sh` copies the runtime without dev files and strips PE debug info (1.9 GB → 776 MB). It keeps the "Wine builtin DLL" markers. `relocate_runtime.py` rewrites 136 Mach-O files to @rpath + @loader_path and ad-hoc re-signs them. GStreamer's compiled plugin and scanner paths are covered by barrel setting GST_PLUGIN_SYSTEM_PATH_1_0/GST_PLUGIN_SCANNER_1_0 from BARREL_LIBS. Check: a fresh bottle created with dist/runtime, DXVK on, passes the D3D11 smoke test (Apple M2, 120 frames OK). DYLD_PRINT_LIBRARIES showed 62 images from dist/ and 0 from build/; the first check, run through perl, had DYLD_* stripped by SIP. App settings fall back to `Resources/runtime` and `Resources/recipes` when unset; empty saved values now count as unset.
