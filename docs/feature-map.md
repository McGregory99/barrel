# CrossOver 26.3 — Feature Map (clean-room inventory)

Source: metadata inventory of the installed bundle `~/Applications/CrossOver.app`
(Info.plist, entitlements, bundle layout, shipped config/data files, `--help` output
of the command-line tools). No proprietary code was decompiled or copied. This
document describes **what** the product does, not **how** CodeWeavers implemented it.

Build: `26.3.0.39832` (`cxoffice-26.3.0rc2`, 2026-07-15), bundle id
`com.codeweavers.CrossOver`, min macOS 10.15.

## 1. Architecture (observed layout)

| Layer | Observed | Licensing note |
|---|---|---|
| GUI app | `MacOS/CrossOver` (2.3 MB) + `Python.framework` + `MainWindow.nib`, 44 localizations | Proprietary — reimplement from scratch |
| Updater | `Sparkle.framework`, feed `codeweavers.com/xml/versions/cxmac.xml` | Sparkle is MIT — reuse |
| Management tools | `bin/cx*` Perl scripts (`cxbottle`, `cxstart`, `cxmenu`, `cxassoc`, …) | © CodeWeavers — reimplement from CLI behavior only |
| Windows runtime | `bin/wine`, `wineserver`, `wineloader`, `lib/wine/{i386-windows,x86_64-windows,x86_64-unix}` | LGPL — get patched source from codeweavers.com/crossover/source |
| D3D → Vulkan | `lib/dxvk` | zlib — open source |
| D3D → Metal | `lib/dxmt` | open source (DXMT) |
| D3D → Metal (Apple) | `lib64/apple_gptk/external/D3DMetal.framework` | Apple GPTK license — check redistribution terms |
| Media | `lib64/gstreamer-1.0`, glib, gnutls, freetype | LGPL/open |
| Utilities | `cabextract`, `unrar`, `ps2pdf`/Ghostscript (print to PDF) | various open licenses (unrar is freeware) |

## 2. Feature list

### F1 — Bottles (isolated Wine prefixes)
- Create / copy / delete / set default bottle (`cxbottle --create|--copy|--delete|--default`).
- Templates (Windows version emulated): win98, win2000, winxp(_64), winvista(_64),
  win7(_64), win8(_64), win10(_64), win11_64.
- Template parameters: `NAME=VALUE` and `SECTION:KEY=VALUE` for bottle config.
- Scopes: private (per user) vs managed (system-wide, read-only desktopdata).
- Per-bottle UUID (`--new-uuid`, `--get-uuid`), status, description.
- Bottle upgrade policy per path (Delete / LinkDir / Link / Registry merge / Copy / Ignore)
  when CrossOver updates a bottle (`bottle_data/cxbottle.conf [ManagedUpdatePolicy]`).
- Per-bottle environment variables (`[EnvironmentVariables]`).

### F2 — Archive / export
- Export bottle as `.cxarchive` (tar/cpio, gzip/bzip2), restore from archive.
- Package bottle as `.deb` / `.rpm` (Linux heritage; low priority on Mac).

### F3 — Launching Windows programs & documents
- `cxstart`: run a program or open a document via Windows file associations.
- Options: restrict extensions, force MIME / Windows class / verb, working dir,
  named Wine desktop.
- Opens `.exe` and `.lnk` directly from Finder (document types in Info.plist).

### F4 — Desktop integration
- Windows Start-menu entries → macOS launchers (`cxmenu`, `MenuRoot`, `MenuStrip`).
- File associations Windows ↔ macOS (`cxassoc`, `cxwinassoc`, MIME alias table,
  ignore lists for exe/htm/lnk/txt/url).
- Open native macOS files/URLs from Windows apps (`cxnativeopen`).
- Shell links (`wineshelllink`).

### F5 — Installer / CrossTie (automated install recipes)
- `.tie` / `.c4p` installation profiles, signed (`tie.pub`), `crossover-crosstie` URL scheme.
- Recipe engine pulls dependencies (fonts, runtimes, redistributables) and applies fixes.
- Fix knowledge base `cxfixes.xml` (~2000 `fixfor` rules, ~1700 packages, distro-specific).
- Hosted "Install Software" catalog backed by codeweavers.com (online).

### F6 — Graphics backend selection (per bottle)
- wined3d (OpenGL), DXVK (D3D9–11 → Vulkan via MoltenVK), DXMT (D3D10/11 → Metal),
  D3DMetal / GPTK (D3D11/12 → Metal).
- Other per-bottle toggles to confirm in the UI (e.g. ESync/MSync, high-resolution mode).

### F7 — System & security
- Entitlements: camera, microphone, Apple Events, unsigned executable memory (JIT).
- Outlook attachment security, blocked extensions list.
- Antivirus scan hook (`cxavscan`), simulated reboot (`cxreboot`), privilege helper (`cxsu`).
- Print to PDF (`cxps2pdf` → Ghostscript).

### F8 — Diagnostics
- System info collection (`cxgetsysinfo`), log filtering (`cxlogfilter`), debug channels.

### F9 — Product shell
- Auto-update (Sparkle), licensing/trial (**out of scope — do not replicate or bypass**),
  44 localizations.

## 3. Reimplementation sources (legal)
1. Wine + CodeWeavers patches: published source tarball for 26.3.
2. Upstream Wine, DXVK, DXMT, MoltenVK, GStreamer.
3. Apple Game Porting Toolkit (D3DMetal) — verify redistribution license.
4. Open references: Whisky (SwiftUI front-end), Kegworks/Wineskin.
5. Behavior of the installed app observed through normal use and its CLI `--help`.

## 4. Open questions (to confirm by using the app, not by decompiling)
- Exact per-bottle settings exposed in the GUI (graphics toggles, sync mode, Retina).
- CrossTie file format details (check public CodeWeavers docs / published source).
- Which `cxfixes.xml` rules matter on macOS vs Linux only.
