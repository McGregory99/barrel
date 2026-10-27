# Source changes to third-party components

barrel ships builds of LGPL components. These are the exact changes made to them, so anyone can rebuild
the same binaries (LGPL §6). Apply with `git am` on top of the stated base.

| Component | Base | Patches |
|---|---|---|
| Wine | upstream tag `wine-11.0` (`db11d0fe6a16`, "Release 11.0") | `wine/0001` = all CrossOver 26.3 Wine changes (from CodeWeavers' LGPL source tarball `crossover-sources-26.3.0.tar.gz`); `wine/0002`–`0006` = this project's changes (see `docs/wine-patches.md`) |
| DXVK | 1.10.3 as shipped in the CrossOver 26.3 source tarball (`sources/dxvk`) | `dxvk/0001` = build fixes for mingw-w64 14 / GCC 16 |
| MoltenVK, SPIRV-Cross | CrossOver 26.3 source tarball (`sources/moltenvk`) | none |
| DXMT | github.com/3Shain/dxmt `50102f9` (submodules as pinned there) | none |
| GLib, GStreamer, gnutls, FreeType | CrossOver 26.3 source tarball | none (build flags only: `scripts/build-*.sh`) |
| nettle 3.10, FFmpeg 6.1.2 | official release tarballs (sha256 pinned in the build scripts) | none |

Regenerate after changing a component:
`git -C upstream/wine-11.0 format-patch -o ../../patches/wine db11d0f..HEAD`
