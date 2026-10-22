# Feature: elegant README with animated use cases
Objective: a public-facing README that explains what barrel is and how it works, with animations per use case.
Branch: `feat/engine-cli-graphics` · Delivery: ask-on-risk · Test runner: none (docs); structural checks (SVG validity, rendering on GitHub).

## Specs
- S1: "tenemos que hacer un readme elegante, con casos de uso hechos con animaciones que expliquen como funciona la app"
  - Assumption: animations are self-contained animated SVGs (render in GitHub `<img>`, light/dark aware) and GIFs recorded from the real app; terminal animations replay real captured `barrel` output, never invented output.
  - Assumption: README in English (artifact language rule).
- S2: "Tambien quiero que hagas una landing page, inspirandote en esta estetica: https://lapis.lvrpiz.com/"
  - Reference aesthetic (observed): Inter, very tight display type (-0.04em), small burnt-orange eyebrow labels (#b74c1b), ink #1c1c1e, muted #595d63, hairlines #e7e7e5, alternating white / #f5f6f7 / warm #f7f6f2 sections, real product shots, tabbed feature block, 3-column features with a hairline above each, dark pill primary button + outline secondary.
  - Assumption: hosted on GitHub Pages from this repo; English; reuses the README animations.

## Tasks
| ID | Specs | Route | Status | Evidence |
|----|-------|-------|--------|----------|
| T1 | S1 | inline | pending | capture real CLI output for each use case in a scratch BARREL_HOME |
| T2 | S1 | inline | pending | animated SVG: how it works (Windows .exe → Wine → DXVK/DXMT → Metal) |
| T3 | S1 | inline | pending | animated SVG terminal casts per use case (play Steam games, per-game graphics, launchers) |
| T4 | S1 | inline | pending | GIF of the real Barrel.app (bottles, Install Software, Create Launcher) |
| T5 | S1 | inline | pending | README.md rewrite, pushed, verified rendering on github.com |
| T6 | S2 | inline | pending | landing page `site/` + GitHub Pages workflow, verified live |
| T0 | S1 | inline | done `fix(cli)` ×2 | fixes found while recording: CLI from Barrel.app ignored bundled recipes; maintenance commands flooded the terminal with MoltenVK/msync output |

## Log
- L1: 2026-10-22 user: "Vale escucha pues ahora tenemos que hacer un readme elegante, con casos de uso hechos con animaciones que expliquen como funciona la app"
- L2: Tools available: ffmpeg only (no vhs/asciinema/gifski). Hence hand-authored animated SVG + ffmpeg GIFs from screen recordings.
- L3: 2026-10-22 user (mid-turn): "Tambien quiero que hagas una landing page, inspirandote en esta estetica: https://lapis.lvrpiz.com/"
- L4: T0. Recording real output exposed two CLI defects. (1) `barrel recipes` from Barrel.app listed nothing: the CLI only read $BARREL_HOME/Recipes; it now also reads `Resources/recipes` (last, so user recipes win) — commit 9462aaf. (2) every maintenance command printed MoltenVK's 111-extension info log and wineserver's msync banner; now MVK_CONFIG_LOG_LEVEL defaults to 1 and unattended commands capture stderr, forwarding it only when the command fails. Tests: 98 pass (2 new: chatter hidden on success; output + mvk=1 shown on failure). Re-recorded session is clean: `barrel install steam` 45 s, `create` 25 s.
