# barrel

Command-line bottle manager for Wine on macOS (clean-room reimplementation of the
CrossOver bottle workflow; see `../docs/feature-map.md`, features F1–F4).

```sh
swift build -c release
export BARREL_WINE=/path/to/wine          # default: 'wine' in PATH
export BARREL_HOME=~/somewhere            # default: ~/Library/Application Support/Barrel

barrel templates                          # win98 … win11 (all bottles are 64-bit WoW64)
barrel create Office --template win10 --description "Office 2016"
barrel list                               # '*' marks the default bottle
barrel default Office                     # set; 'barrel default --unset' clears
barrel run --bottle Office ~/Downloads/setup.exe /S
barrel run ~/Documents/report.docx        # opens via Windows associations, default bottle
barrel copy Office Office-backup
barrel export Office office.tar.gz
barrel restore office.tar.gz --as Office2 # new name ⇒ new identity
barrel delete Office-backup --force

# Graphics (per bottle) and MSync
export BARREL_LIBS=…/build/deps/lib       # libMoltenVK.dylib for Vulkan/DXVK
export BARREL_DXVK=…/build/dxvk/install   # x64/ and x32/ DLLs
export BARREL_GPTK=~/GPTK                 # your own Apple Game Porting Toolkit (not bundled)
barrel graphics Office                    # show: wined3d | dxvk | dxmt | d3dmetal
barrel graphics Office dxvk               # copies DXVK DLLs, writes the D3D load order to the registry
barrel graphics Steam wined3d --app steamwebhelper.exe   # per-executable override (AppDefaults)
barrel msync Office off                   # MSync is on by default
```

Install recipes (format: `../docs/recipes.md`; examples in `../recipes/`):

```sh
barrel recipes --recipes-dir ../recipes                 # list recipes ($BARREL_HOME/Recipes is read too)
barrel install windows-app-base --recipes-dir ../recipes --bottle Office
barrel install vcredist-x64 --recipes-dir ../recipes    # no --bottle: bottle 'vcredist-x64' is created
```

macOS launchers (F4): an app in `~/Applications/Barrel` (or `$BARREL_LAUNCHERS`) that runs a
program in a bottle, with the icon taken from a Windows executable:

```sh
S="$BARREL_HOME/Bottles/steam/drive_c/Program Files (x86)/Steam"
barrel launcher create steam "$S/steam.exe" --name Stonewards \
  --icon-from "$S/steamapps/common/Stonewards/Stonewards.exe" -- -applaunch 4502710
barrel launcher list
barrel launcher remove Stonewards
```

The launcher stores the current `BARREL_*` variables, because apps opened from Finder do not
inherit the shell environment.

Downloads are SHA-256 verified and cached in `$BARREL_HOME/Downloads`.

The Direct3D DLL load order is written to the bottle's registry (`DllOverrides`, and
`AppDefaults\<exe>\DllOverrides` for `--app`), so per-executable choices win over the bottle default.
`run` launches Wine with the bottle's environment: `CX_ACTIVE_GRAPHICS_BACKEND`, `WINEMSYNC=1`, and `DYLD_FALLBACK_LIBRARY_PATH` so Wine
can `dlopen` MoltenVK.

Layout: `$BARREL_HOME/Bottles/<name>/` is the Wine prefix plus `barrel.json` metadata;
`$BARREL_HOME/settings.json` holds the default bottle.

Tests: `swift test`.

## License

GPL-3.0-or-later. See [LICENSE](../LICENSE).
