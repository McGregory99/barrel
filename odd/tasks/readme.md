# Feature: elegant README with animated use cases
Objective: a public-facing README that explains what barrel is and how it works, with animations per use case.
Branch: `feat/engine-cli-graphics` · Delivery: ask-on-risk · Test runner: none (docs); structural checks (SVG validity, rendering on GitHub).

## Specs
- S1: "tenemos que hacer un readme elegante, con casos de uso hechos con animaciones que expliquen como funciona la app"
  - Assumption: animations are self-contained animated SVGs (render in GitHub `<img>`, light/dark aware) and GIFs recorded from the real app; terminal animations replay real captured `barrel` output, never invented output.
  - Assumption: README in English (artifact language rule).

## Tasks
| ID | Specs | Route | Status | Evidence |
|----|-------|-------|--------|----------|
| T1 | S1 | inline | pending | capture real CLI output for each use case in a scratch BARREL_HOME |
| T2 | S1 | inline | pending | animated SVG: how it works (Windows .exe → Wine → DXVK/DXMT → Metal) |
| T3 | S1 | inline | pending | animated SVG terminal casts per use case (play Steam games, per-game graphics, launchers) |
| T4 | S1 | inline | pending | GIF of the real Barrel.app (bottles, Install Software, Create Launcher) |
| T5 | S1 | inline | pending | README.md rewrite, pushed, verified rendering on github.com |

## Log
- L1: 2026-10-22 user: "Vale escucha pues ahora tenemos que hacer un readme elegante, con casos de uso hechos con animaciones que expliquen como funciona la app"
- L2: Tools available: ffmpeg only (no vhs/asciinema/gifski). Hence hand-authored animated SVG + ffmpeg GIFs from screen recordings.
