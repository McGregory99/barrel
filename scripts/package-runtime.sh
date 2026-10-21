#!/bin/sh
# Copies the built runtime (Wine, native deps, DXVK, DXMT) into a relocatable tree for Barrel.app:
#   <out>/wine   Wine install (bin/, lib/wine/)
#   <out>/deps   native libraries (MoltenVK, FreeType, GnuTLS, GStreamer, FFmpeg) and gst-plugin-scanner
#   <out>/dxvk   DXVK x64/, x32/
#   <out>/dxmt   DXMT system32/, syswow64/, x86_64-windows/, i386-windows/, x86_64-unix/
# Development files (*.a, headers, pkg-config, docs) are left out, PE debug info is stripped, and
# Mach-O links into build/ are rewritten to @rpath by relocate_runtime.py.
# Usage: scripts/package-runtime.sh [out-dir]   (default: dist/runtime)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/build
OUT=${1:-$ROOT/dist/runtime}

rm -rf "$OUT"
mkdir -p "$OUT"
dev="--exclude=*.a --exclude=include/ --exclude=pkgconfig/ --exclude=share/man/ --exclude=share/doc/ --exclude=share/gtk-doc/ --exclude=share/aclocal/ --exclude=share/gettext/"
# shellcheck disable=SC2086
rsync -a $dev "$BUILD/install/" "$OUT/wine/"
# shellcheck disable=SC2086
rsync -a $dev --exclude=bin/ --exclude=lib/libMoltenVK.official.dylib "$BUILD/deps/" "$OUT/deps/"
rsync -a --exclude='*.a' "$BUILD/dxvk/install/" "$OUT/dxvk/"
rsync -a --exclude='*.a' "$BUILD/dxmt/install/" "$OUT/dxmt/"

# Strip debug info from PE files with the matching mingw strip (PE32+ → x86_64, PE32 → i686).
find "$OUT" -type f \( -name '*.dll' -o -name '*.exe' -o -name '*.drv' -o -name '*.sys' -o -name '*.ocx' \
    -o -name '*.cpl' -o -name '*.acm' -o -name '*.ax' -o -name '*.tlb' -o -name '*.com' -o -name '*.vxd' \) |
while IFS= read -r f; do
    case $(file -b "$f") in
        *PE32+*) x86_64-w64-mingw32-strip --strip-debug "$f" 2>/dev/null || true ;;
        *PE32*) i686-w64-mingw32-strip --strip-debug "$f" 2>/dev/null || true ;;
    esac
done

python3 "$ROOT/scripts/relocate_runtime.py" "$OUT" "$BUILD"
du -sh "$OUT"
