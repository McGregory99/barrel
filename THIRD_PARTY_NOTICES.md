# Third-party components

barrel is GPL-3.0-or-later (see `LICENSE`). Its runtime bundles the components below, each under its own
license. Our changes to them are in `patches/` (see `patches/README.md`); the build scripts in `scripts/`
rebuild every binary from these sources.

| Component | Version | License | Source |
|---|---|---|---|
| Wine (with CrossOver 26.3 patches) | 11.0 | LGPL-2.1-or-later | winehq.org; codeweavers.com/crossover/source; `patches/wine/` |
| DXVK | 1.10.3 (CrossOver 26.3) | Zlib | CrossOver 26.3 source tarball; `patches/dxvk/` |
| MoltenVK (CrossOver fork) | 1.2.10 | Apache-2.0 | CrossOver 26.3 source tarball |
| SPIRV-Cross | as pinned by MoltenVK | Apache-2.0 | CrossOver 26.3 source tarball |
| DXMT | `50102f9` | LGPL-2.1-or-later | github.com/3Shain/dxmt |
| LLVM (static, inside DXMT's winemetal.so) | 15.0.7 | Apache-2.0 WITH LLVM-exception | github.com/llvm/llvm-project |
| NVAPI headers (DXMT submodule) | as pinned | MIT | github.com/NVIDIA/nvapi |
| FreeType | CrossOver 26.3 | FTL or GPL-2.0 (dual; used under GPL-2.0-or-later terms compatible with GPL-3) | CrossOver 26.3 source tarball |
| GnuTLS (with bundled libtasn1) | 3.8.3 | LGPL-2.1-or-later | CrossOver 26.3 source tarball |
| Nettle | 3.10 | LGPL-3.0-or-later or GPL-2.0-or-later | ftp.gnu.org/gnu/nettle |
| GMP | CrossOver 26.3 | LGPL-3.0-or-later or GPL-2.0-or-later | CrossOver 26.3 source tarball |
| GLib | 2.78.0 | LGPL-2.1-or-later | CrossOver 26.3 source tarball |
| libffi | GLib wrap | MIT | github.com/libffi/libffi |
| PCRE2 | 10.42 | BSD-3-Clause | github.com/PCRE2Project/pcre2 |
| proxy-libintl | GLib wrap | LGPL-2.0 (Library GPL v2) | github.com/frida/proxy-libintl |
| GStreamer, gst-plugins-base/good/bad, gst-libav | 1.24.4 | LGPL-2.1-or-later | CrossOver 26.3 source tarball |
| ORC | 0.4.38 | BSD-2-Clause | gitlab.freedesktop.org/gstreamer/orc |
| libogg, libvorbis | GStreamer wraps | BSD-3-Clause | xiph.org |
| Opus | GStreamer wrap | BSD-3-Clause | opus-codec.org |
| FLAC | 1.4.3 | BSD-3-Clause (libFLAC) | xiph.org/flac |
| FFmpeg (decoders/parsers only, no GPL parts) | 6.1.2 | LGPL-2.1-or-later | ffmpeg.org |

Not bundled (the user supplies or downloads them; never redistributed):
- Apple Game Porting Toolkit / D3DMetal: Apple license.
- Steam and its Windows DLLs: Valve.
- Windows redistributables installed by recipes (for example the VC++ runtimes): Microsoft. They are downloaded from the vendor and checked by SHA-256.
