# Feature: Steam first, everything else in Advanced
Objective: re-center Barrel on playing Windows Steam games (library, per-game profiles, Dock launchers); bottles, recipes and the CLI stay available as Advanced.
Branch: `feat/steam-first` · Delivery: ask-on-risk · Test runner: `swift test` in barrel/ and app/.

## Specs
- S1: "Me parece bien tu propuesta de Steam primero y lo demás en avanzado" — the proposal accepted:
  - "La primera vez, un botón: «Instalar Steam»."
  - "Después, tu biblioteca de juegos instalados (Barrel puede leerla de los archivos de Steam)."
  - "En cada juego: Jugar, motor gráfico (DXVK / DXMT) y «Añadir al Dock»."
  - Bottles created automatically; manual bottle management, export/copy/restore go to "Avanzado"; recipes: only "Instalar Steam" visible, VC++ and the rest hidden.
- S2: per-game profiles: "una ficha con los ajustes que necesita un juego concreto para funcionar bien en Mac", applied automatically when the game is launched; keyed by Steam app id; "La mayoría de juegos funcionan con los ajustes por defecto"; profiles are the exceptions.
- S3: "en la landing page yo no enfocaría todo como que solamente es para Steam, pero al final pondría algo rollo si te quieres meter en serio en esta mierda, puedes hacer todo esto. En la parte de avanzado."
- S4: a skill with clear instructions to create a tested game profile ("unas instrucciones claras de cómo tiene que hacerse y cómo tiene que crearse el JSON").
  - Assumption: the skill lives in the repo (`skills/`), drives the `barrel` CLI; no MCP server.

## Tasks
| ID | Specs | Route | Status | Evidence |
|----|-------|-------|--------|----------|
| T1 | S1 | inline | done | Steam library reader: libraryfolders.vdf + appmanifest_*.acf → installed games (app id, name, install dir) |
| T2 | S2 | inline | done | game profiles: format, bundled `profiles/`, applied on launch; `barrel games` / `barrel play` |
| T3 | S1 | inline | done | recipes can be `hidden` (dependencies); VC++ hidden from app and `barrel recipes` |
| T4 | S1 | inline | done | app: Steam home (Install Steam → library → Play / graphics / Add to Dock); bottles under Advanced |
| T5 | S4 | inline | done | `skills/barrel-game-profile/SKILL.md` + docs/profiles.md |
| T6 | S3 | inline | pending | landing + README: Steam-first story, new screenshots, "Advanced" section at the end |

## Log
- L1: 2026-10-22 user: "Me parece bien tu propuesta de Steam primero y lo demás en avanzado, y de hecho, en la landing page yo no enfocaría todo como que solamente es para Steam, pero al final pondría algo rollo si te quieres meter en serio en esta mierda, puedes hacer todo esto. En la parte de avanzado. por otro lado, si cada juego necesita un perfil me estás diciendo que tendríamos que probar todos los juegos del mundo para saber cuál es el perfil de cada uno."
- L2: Steam data (user's bottle): `steamapps/libraryfolders.vdf` lists library paths (Windows paths) and app ids; `appmanifest_<id>.acf` has appid, name, installdir, StateFlags (4 = fully installed), LastOwner (a SteamID: never copy into fixtures).
- L3: T1. `SteamLibrary.installedGames(prefix:)` reads libraryfolders.vdf (Windows paths mapped through dosdevices, resolved, deduplicated) and appmanifest_*.acf (StateFlags bit 4; Steamworks redistributables 228980 skipped); `KeyValues` parses Valve's text format. On the user's bottle it finds Stonewards (4502710). Commit 4165481.
- L4: T2. `GameProfile` (+ parser, catalog: $BARREL_HOME/Profiles, extra dir, then bundled), `BottleService.play` writes graphics + DLL overrides to AppDefaults\<exe> only when the profile fingerprint changes (new optional `appliedProfiles` in bottle metadata, old metadata decodes), never over the player's own per-game choice, then runs `steam.exe -applaunch <id> <profile args> <args>`. `gameGraphics` reports player/profile/bottle. CLI: `barrel games`, `barrel play`, `barrel launcher game` (launcher script runs `barrel play`). First profile: profiles/4502710.json. 115 tests pass. `barrel games` on the user's bottle: "4502710 Stonewards dxvk (player) profile: works". Not run end to end: the user's Steam session was open. Known gap: if a player later removes their own per-game choice, the profile is not re-applied until the profile changes.
- L5: T3. Recipes accept `"hidden": true` (strict boolean); `RecipeCatalog.visible` drops them; the app lists visible recipes; `barrel recipes` lists visible, `--all` adds hidden. vcredist-x64/x86 hidden (still installable as dependencies of windows-app-base). 116 barrel + 29 app tests pass.
- L6: T4. App: sidebar "Play › Library" (default) + "Advanced" (bottles; + menu: New Bottle, Install Software, Restore). Library states: Welcome with "Install Steam" (recipe `steam`, own bottle), "No games yet" with Open Steam / Refresh, or a grid of game cards (icon read from the exe, profile badge, Graphics menu DXVK/DXMT/wined3d with its source, Play, Add to Dock → game launcher running `barrel play`). Launching does not hold the busy state (Steam keeps running); a short "Starting …" note shows instead. Gateway: steamBottle (bottle with steam.exe, prefers "steam"), games, play, openSteam, setGameGraphics, createGameLauncher; settings gain profilesDirectory (bundled `profiles`, env BARREL_PROFILES). Tests: app 37 pass (6 library view-model tests, 2 gateway tests over an on-disk fake Steam library). Checked in the packaged app: real data shows Stonewards with its icon and "Tested: works"; an empty data folder shows Welcome; clicking Install Steam installed Steam into a scratch folder and the screen switched to "No games yet". Play was not clicked (the user's Steam session was open).
- L7: T5. `skills/barrel-game-profile/SKILL.md` (frontmatter name/description for agent skill loaders): needs a played result; iterate with a draft in $BARREL_HOME/Profiles (re-applied when it changes); symptom → setting table; status rules; notes template; no environment variables; no copying from proprietary products. Known gap noted there: a player's own per-game graphics choice cannot be cleared yet and overrides profiles.
