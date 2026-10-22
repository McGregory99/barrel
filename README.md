# barrel

An open-source Windows compatibility layer for macOS on Apple Silicon, built on Wine 11 with the
CrossOver 26.3 source patches CodeWeavers publishes under the LGPL. It runs Windows games and apps
in per-app "bottles" with DXVK or DXMT for Direct3D, and ships as a CLI (`barrel`) plus a SwiftUI
app (`Barrel.app`).

Not affiliated with or endorsed by CodeWeavers. No proprietary CrossOver code is used.

- `barrel/` — core library and CLI ([README](barrel/README.md))
- `app/` — SwiftUI app ([README](app/README.md))
- `recipes/` — install recipes ([docs](docs/recipes.md))
- `scripts/` — engine build, packaging, signing and smoke tests
- `patches/` — our patches to Wine and DXVK ([docs](docs/wine-patches.md))

License: GPL-3.0-or-later ([LICENSE](LICENSE)). Bundled components keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
