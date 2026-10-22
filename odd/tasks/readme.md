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
- S3: "podrias meter un iconito con dos lenguajes epanol ingles y que se cambie el idioma en la landing?"

## Tasks
| ID | Specs | Route | Status | Evidence |
|----|-------|-------|--------|----------|
| T1 | S1 | inline | done | capture real CLI output for each use case in a scratch BARREL_HOME |
| T2 | S1 | inline | done | animated SVG: how it works (Windows .exe → Wine → DXVK/DXMT → Metal) |
| T3 | S1 | inline | done | animated SVG terminal casts per use case (play Steam games, per-game graphics, launchers) |
| T4 | S1 | inline | done | GIF of the real Barrel.app (bottles, Install Software, Create Launcher) |
| T5 | S1 | inline | done `1b9b4cd` | README.md rewrite, pushed, verified rendering on github.com |
| T6 | S2 | inline | done `8da91fe` | landing page `site/` + GitHub Pages workflow, verified live |
| T7 | S3 | inline | done | ES/EN switch (globe + ES / EN) in the landing nav; Spanish copy in `site/i18n-es.js` |
| T0 | S1 | inline | done `fix(cli)` ×2 | fixes found while recording: CLI from Barrel.app ignored bundled recipes; maintenance commands flooded the terminal with MoltenVK/msync output |

## Log
- L1: 2026-10-22 user: "Vale escucha pues ahora tenemos que hacer un readme elegante, con casos de uso hechos con animaciones que expliquen como funciona la app"
- L2: Tools available: ffmpeg only (no vhs/asciinema/gifski). Hence hand-authored animated SVG + ffmpeg GIFs from screen recordings.
- L3: 2026-10-22 user (mid-turn): "Tambien quiero que hagas una landing page, inspirandote en esta estetica: https://lapis.lvrpiz.com/"
- L4: T0. Recording real output exposed two CLI defects. (1) `barrel recipes` from Barrel.app listed nothing: the CLI only read $BARREL_HOME/Recipes; it now also reads `Resources/recipes` (last, so user recipes win) — commit 9462aaf. (2) every maintenance command printed MoltenVK's 111-extension info log and wineserver's msync banner; now MVK_CONFIG_LOG_LEVEL defaults to 1 and unattended commands capture stderr, forwarding it only when the command fails. Tests: 98 pass (2 new: chatter hidden on success; output + mvk=1 shown on failure). Re-recorded session is clean: `barrel install steam` 45 s, `create` 25 s.
- L5: T0 cont. Screenshots exposed two app defects, fixed: the sidebar's New/Install/Restore buttons sat in a toolbar overflow (») — sidebar now 220–240 pt wide and Restore folded into a New Bottle split menu (32acb19); Install Software showed maintainer notes (stale-hash advice) as descriptions — recipes now carry a short `description` plus a `notes` field the app never shows (885093a, parser test added; 99 barrel tests pass, 29 app tests pass).
- L6: T1–T4. Real session recorded in a scratch BARREL_HOME (later moved to /Users/Shared/Barrel so screenshots show a neutral path). `scripts/render_media.py` turns `docs/media/casts/*.txt` (verbatim output; home shown as ~, wrapped at 76 columns) into CSS-animated terminal SVGs and draws `how-it-works-{light,dark}.svg` (SMIL dots + CSS dash flow). Checked by freezing animations at chosen times in headless Chrome. App tour GIF (842 KB, 3 real screenshots with crossfades) and 1600 px PNGs via ffmpeg. A Finder screenshot of the launcher was discarded because it showed the user's home folder name.
- L7: T5/T6. README rewritten (hero GIF, four use cases, backend table, how-it-works with <picture> light/dark, performance table with the one-scene caveat, build steps, layout, license). Landing `site/` follows the Lapis tokens; verified at 1440 px and in a 390 px iframe (no horizontal overflow). Copy claims checked against the code: app does not expose per-app graphics, so the page says "covers the everyday work"; memory claim is 1.00 vs 1.65 GB ("about 40% less").
- L8: Published. README renders on github.com with all animations playing; landing live at https://mcgregory99.github.io/barrel/ (HTTP 200 for page and media). Pages enabled with build_type=workflow; the push-triggered run failed only because Pages was not enabled yet and passed on re-run. Demo data in /Users/Shared/Barrel removed afterwards.
- L9: 2026-10-22 user: "podrias meter un iconito con dos lenguajes epanol ingles y que se cambie el idioma en la landing?"
- L10: T7. English stays the page's own text; 62 strings (text, alt, data-alt, aria-label) carry data-i18n keys and Spanish lives in `site/i18n-es.js`. First visit follows the browser language, the choice is kept in localStorage (wrapped in try/catch); <html lang>, title and meta description switch too. Checks: es-ES browser opens in Spanish, en-US in English; clicking ES then EN restores the page byte-for-byte (body innerHTML equal, 18115 chars); Spanish layout checked at 1440 px and 390 px.
