# barrel

Command-line bottle manager for Wine on macOS (clean-room reimplementation of the
CrossOver bottle workflow; see `../docs/feature-map.md`, features F1–F3).

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
barrel graphics Office dxvk               # copies DXVK DLLs into the prefix
barrel msync Office off                   # MSync is on by default
```

`run` launches Wine with the bottle's environment: `WINEDLLOVERRIDES` for the D3D DLLs,
`CX_ACTIVE_GRAPHICS_BACKEND`, `WINEMSYNC=1`, and `DYLD_FALLBACK_LIBRARY_PATH` so Wine
can `dlopen` MoltenVK.

Layout: `$BARREL_HOME/Bottles/<name>/` is the Wine prefix plus `barrel.json` metadata;
`$BARREL_HOME/settings.json` holds the default bottle.

Tests: `swift test`.
