# SwiftUI app and install recipes (phases 6–7)
Objective: native macOS front-end over BarrelCore, and an open recipe format to install Windows apps into bottles.
Branch: `feat/engine-cli-graphics` (shared with phases 3–5) · Delivery: ask-on-risk · Test runner: Swift Testing (`swift test`).

## Specs
- S1 (phase 6 — GUI): "App nativa sobre `BarrelCore`: lista de bottles, instalar programas, ajustes y actualizaciones con Sparkle." Earlier plan wording: "Lista de bottles, instalar programas, ajustes por bottle y actualizaciones con Sparkle." Acceptance: "hace lo mismo que el CLI, sin usar la terminal."
- S2 (phase 7 — recipes): "Formato abierto tipo CrossTie: dependencias, arreglos y ajustes por aplicación." Earlier plan wording: "Un formato propio y abierto para recetas de instalación: dependencias, arreglos y ajustes por aplicación (F5)."
- Assumption: Sparkle updates are deferred until there is a signed app bundle (phase 9); S1 ships without them for now.
- Assumption: recipes are JSON files (no extra dependency), and per-app DLL overrides are written to the prefix registry (`HKCU\Software\Wine\DllOverrides`), so no BarrelCore change is needed.

## Tasks
| ID | Specs | Route | Status | Evidence |
|---|---|---|---|---|
| T1 | S1 | delegated (writer A, parallel with T2) | in progress | surface: `app/**` |
| T2 | S2 | delegated (writer B, parallel with T1) | in progress | surface: `barrel/Sources/BarrelRecipes/**`, `barrel/Tests/BarrelRecipesTests/**`, `barrel/Sources/barrel/main.swift`, `barrel/README.md`, `recipes/**`, `docs/recipes.md` |
| T3 | S1,S2 | inline | pending | seam check: full `swift test` in both packages + GUI uses recipes |

## Log
- L1 (2026-10-21): "Podemos empezar y paralelizar algunas de las tareas que faltan? sobretodo la 6 y 7 que son las mas importantes"
- L2: Route evidence — Writer trigger (a): two independent units with disjoint edit surfaces, each heavier than a subagent start, launched together. Parent owns git and `barrel/Package.swift` (pre-wired the `BarrelRecipes` target before launch) and keeps working on phases 3–5 in `BarrelCore`.
