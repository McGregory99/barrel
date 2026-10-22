# Game profiles (format version 1)

A game profile records what one Steam game needs to run well in Barrel. Barrel applies it when it
launches the game (`barrel play`, a game launcher, or Play in the app). Most games need no profile:
the Steam bottle's defaults (DXVK, MSync and the fixes in the Steam recipe) are enough. A profile is for the
exceptions, and every profile should come from actually playing the game.

Profiles live one per file, named after the Steam app id: `profiles/<appid>.json` in this repository
(bundled into Barrel.app), or `$BARREL_HOME/Profiles/<appid>.json` for your own. Your own file wins
over a bundled one with the same app id.

```json
{
  "formatVersion": 1,
  "steamAppId": 4502710,
  "name": "Stonewards",
  "status": "works",
  "executable": "Stonewards.exe",
  "graphics": "dxvk",
  "dllOverrides": { "xinput1_3": "native,builtin" },
  "launchArguments": ["-dx11"],
  "notes": "What was tested, on which Mac, and why each setting is there."
}
```

| Field | Rules |
|---|---|
| `formatVersion` | required, `1` |
| `steamAppId` | required; the number in the game's store URL (`store.steampowered.com/app/<id>`) |
| `name` | required |
| `status` | required: `works`, `issues` (playable with known problems) or `broken` |
| `executable` | optional; file name of the process that renders (no folders). When missing, Barrel guesses: an Unreal `*-Shipping.exe`, else an `.exe` named like the game, else the largest one, ignoring crash handlers, uninstallers and redistributables |
| `graphics` | optional; `wined3d`, `dxvk` or `dxmt` for this game. A backend the player picks for the game wins. `d3dmetal` cannot be set per game |
| `dllOverrides` | optional; Wine DLL overrides for this game's executable: `native`, `builtin`, `native,builtin`, `builtin,native`, or `""` to disable the DLL |
| `launchArguments` | optional; passed to the game after `steam -applaunch <id>` |
| `notes` | optional; for people reading the profile |

## How Barrel applies a profile

`graphics` and `dllOverrides` are written to Wine's per-executable settings
(`HKCU\Software\Wine\AppDefaults\<executable>\DllOverrides`), so they affect only that game. Barrel
remembers which version of a profile it wrote into a bottle and rewrites only when the profile
changes. Environment variables cannot be scoped to one game this way, so profiles do not set them;
a variable every game needs belongs in Barrel's defaults.

## Commands

```sh
barrel games                     # installed games: graphics and who chose it, profile status
barrel play Stonewards           # by name or app id; applies the profile, then starts the game
barrel launcher game Stonewards  # a Mac app with the game's icon that runs 'barrel play'
```
