---
name: barrel-game-profile
description: Make a Windows Steam game run well in Barrel and record the result as a tested game profile (profiles/<appid>.json). Use when a game crashes, shows a black screen, renders wrong, stutters or will not start in Barrel, or when someone asks to "add a profile", "make <game> work" or "test <game>" in Barrel.
---

# Create a tested game profile

A profile is only worth adding when it was **played**. Never write a profile from guesses, forum posts
or another layer's settings alone: those are starting points to try, not results. The format is in
`docs/profiles.md`; read it first.

## What you need

- Barrel's `barrel` CLI (inside `Barrel.app/Contents/MacOS/barrel`, or `barrel/.build` with `BARREL_*` set).
- A bottle with Steam (`barrel install steam`), the player signed in, and the game installed.
- The player at the Mac. You cannot see the game window unless they share screenshots, and only they can
  say whether it plays well. Ask them to describe what they see after each attempt.

## Steps

1. **Find the game.** `barrel games` prints `appid  name  graphics (source)  profile`. Note the app id
   and whether the graphics come from `player`. A player's own choice (set with
   `barrel graphics <bottle> <backend> --app <exe>` or the app's Graphics menu) overrides any profile,
   so tell the player when one is set: your profile tests will not change graphics for that game.

2. **Baseline.** Run `barrel play <appid>` with no profile and capture Wine's output:
   `WINEDEBUG=err+all,fixme-all barrel play <appid> 2>&1 | tee ~/barrel-<appid>.log`
   Ask the player what happened. Classify it: does not start, crashes (when?), black or white screen,
   missing or wrong textures, very slow, freezes, no sound, controller or mouse problems.

3. **Write a draft profile** in `$BARREL_HOME/Profiles/<appid>.json` (default
   `~/Library/Application Support/Barrel/Profiles`). That folder wins over bundled profiles, and Barrel
   re-applies a profile every time its contents change, so you iterate by editing this one file and running
   `barrel play <appid>` again. Start with `"status": "broken"` until it plays.

4. **Try one change at a time**, cheapest first, and keep a table of what you tried and what the player saw:

   | Symptom | Try |
   |---|---|
   | Black screen, crash at start, missing textures | `"graphics"`: `dxvk`, then `dxmt` (D3D10/11 only), then `wined3d` |
   | Game picks a D3D12 or Vulkan renderer and fails | a launch argument that forces D3D11, e.g. `"launchArguments": ["-dx11"]` (Unity: `-force-d3d11`) |
   | Wrong `executable` guessed (settings have no effect) | set `"executable"` to the process that renders; check `ps` while it runs |
   | A Windows DLL the game ships misbehaves under Wine | `"dllOverrides": {"<dll>": "builtin"}`; to prefer the game's copy, `"native,builtin"` |
   | Video cutscenes are black | note it as an issue; video support is limited |

   Read the log after each run: lines with `err:` that appear right before a crash usually name the
   DLL or feature involved.

5. **Decide the status.** `works`: plays start to finish of a real session without problems the player
   would notice. `issues`: playable with known problems; list them in `notes`. `broken`: not playable
   with any setting you tried; still worth recording so nobody repeats the same attempts.

6. **Write the notes for the next person**: Mac model and macOS version, Barrel version or commit, what
   you played (menu only, first level, an hour), and why each setting is there. Example:
   `"Played the first two levels on an Apple M2, macOS 26.1. DXMT: DXVK shows black water."`

7. **Check and share.** `barrel games --profiles-dir <folder with the file>` must list the game with
   `profile: <status>` and no warning. To include it in Barrel, copy the file to `profiles/<appid>.json`
   in the repository and open a pull request with the table from step 4.

## Do not

- Do not set environment variables in a profile: they cannot be limited to one game. If every game needs
  one, it belongs in Barrel's defaults (`LaunchEnvironment` in `barrel/Sources/BarrelCore/Graphics.swift`).
- Do not mark a game `works` from the main menu alone; use `issues` with a note instead.
- Do not copy settings or files from CrossOver or other proprietary products.
