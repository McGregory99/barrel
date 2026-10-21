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
```

Layout: `$BARREL_HOME/Bottles/<name>/` is the Wine prefix plus `barrel.json` metadata;
`$BARREL_HOME/settings.json` holds the default bottle.

Tests: `swift test`.
