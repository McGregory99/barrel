# CrossOver 26.3 Wine patches vs upstream Wine 11.0

Inputs (both under `upstream/`, git-ignored):
- `crossover-sources-26.3.0.tar.gz` from codeweavers.com/crossover/source
  (sha256 `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`)
- upstream Wine `wine-11.0` tag (`db11d0fe6a16`, "Release 11.0")

Full diff: `upstream/crossover-26.3-vs-wine-11.0.patch` (22,635 lines).
Totals: 204 files, +10,194 / -662 (includes regenerated `configure`).

## Patch areas (largest first)

| Area | Files | What it adds |
|---|---|---|
| **MSync** | `server/msync.c`, `dlls/ntdll/unix/msync.c` (new) | Mach-semaphore based sync primitives (macOS equivalent of esync/fsync); big perf win for games |
| **D3DMetal glue** | `dlls/winemac.drv/d3dmetal.c`, `d3dmetal_objc.m` (new) | Hooks Apple GPTK D3DMetal into the Mac driver |
| **Mac driver** | `winemac.drv/cocoa_app.m`, `cocoa_icon_utils.m`, `opengl_bcdec.h` (BCn texture decode for GL) | Window/app integration, icons, compressed textures on OpenGL |
| **Loader / process** | `ntdll/loader.c`, `ntdll/unix/{loader,process,signal_x86_64}.c`, `loader/` | Rosetta/x86_64 handling, per-app overrides, startup behavior |
| **Controllers** | `winebus.sys/bus_xbox360.c` (new) | Xbox 360 controller bus |
| **Drives / mounts** | `mountmgr.sys/unixlib.c` | macOS volume handling |
| **Audio** | `winecoreaudio.drv/authorization.m` (new) | Microphone permission prompt (TCC) |
| **Menus** | `winemenubuilder/cxmenu.c` (new) | Start-menu → CrossOver launcher integration |
| **Printing** | `localspl/cups.c` | CUPS printing |
| **Misc compat** | win32u, wined3d, kernelbase, user32, shell32, mshtml, winhttp, msctf, ole32… | App-specific fixes |

## Our own patches (branch `cx-26.3` in `upstream/wine-11.0`, on top of the CX patches)
| Commit | Area | Purpose |
|---|---|---|
| `b4af2ac` | win32u | Restore the `SONAME_LIBVULKAN` guard so the build works without a system Vulkan loader |
| `589cf05` | kernelbase | `AppDefaults\<exe>\AppendCommandLine`: append per-app arguments (Steam's CEF flags) |
| `a8176e4` | ntdll | `WINEDLLPATH_PREPEND`: directories searched before Wine's own dll dir, so replacement builtins (D3DMetal's d3d11/dxgi) win. CX exports `prepend_dll_path` for this purpose |
| `dd0234e` | winecoreaudio | Ask for microphone permission without waiting for the answer: macOS may never answer, which froze games that open voice chat (Stonewards' character select) |
| `4ff6323` | winecoreaudio | List no capture devices until macOS has granted microphone access, without asking: asking aborts the process when the launching app has no NSMicrophoneUsageDescription (Stonewards froze or crawled) |
| `9c8ed0d` | winecoreaudio | A shared render stream on the default device follows macOS default output changes (switching to headphones moves the game's sound) |

## Next steps
- Split the patch per area (`filterdiff`/`splitdiff`) to study each independently.
- Prioritize for the reimplementation: MSync + D3DMetal glue + winemac.drv are the
  macOS-specific core; the rest are compat fixes to cherry-pick as needed.
- Check which of these are already upstreamed in later Wine releases (11.x dev).
