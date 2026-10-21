#!/bin/sh
# Builds the Windows runtime for Apple Silicon (x86_64 under Rosetta) into build/.
# Prerequisites (Homebrew, arm64 is fine for tools): mingw-w64 bison cmake meson ninja glslang.
# Sources (git-ignored, see docs/wine-patches.md):
#   upstream/crossover-26.3/sources  CrossOver 26.3 source tarball
#   upstream/wine-11.0               Wine 11.0 + CX patches (branch cx-26.3)
#   upstream/dxvk-cx                 DXVK 1.10.3 from CX sources + mingw-w64 14 fixes
#   upstream/moltenvk-1.2.10         MoltenVK v1.2.10-rc2 release (universal dylib)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/upstream/crossover-26.3/sources
DEPS=$ROOT/build/deps
JOBS=${JOBS:-8}
export PATH=/opt/homebrew/opt/bison/bin:$PATH

step=${1:-all}

deps() {
    cmake -S "$SRC/freetype" -B "$ROOT/build/freetype-cmake" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DCMAKE_INSTALL_PREFIX="$DEPS" -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
        -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON
    cmake --build "$ROOT/build/freetype-cmake" -j"$JOBS"
    cmake --install "$ROOT/build/freetype-cmake"
    cp "$ROOT/upstream/moltenvk-1.2.10/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$DEPS/lib/"
}

wine() {
    mkdir -p "$ROOT/build/wine64"
    cd "$ROOT/build/wine64"
    PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig arch -x86_64 "$ROOT/upstream/wine-11.0/configure" \
        --prefix="$ROOT/build/install" --enable-archs=i386,x86_64 \
        CC="clang -arch x86_64" OBJC="clang -arch x86_64" CFLAGS="-O2" \
        CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib -Wl,-rpath,$DEPS/lib" \
        FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype"
    arch -x86_64 make -j"$JOBS"
    arch -x86_64 make install
}

dxvk() {
    for bits in 64 32; do
        meson setup --reconfigure --cross-file "$ROOT/upstream/dxvk-cx/build-win$bits.txt" \
            --buildtype release --prefix "$ROOT/build/dxvk/install" --bindir "x$bits" --libdir "x$bits" \
            -Dcpp_args="-include cstdint" "$ROOT/build/dxvk/build$bits" "$ROOT/upstream/dxvk-cx" 2>/dev/null ||
        meson setup --cross-file "$ROOT/upstream/dxvk-cx/build-win$bits.txt" \
            --buildtype release --prefix "$ROOT/build/dxvk/install" --bindir "x$bits" --libdir "x$bits" \
            -Dcpp_args="-include cstdint" "$ROOT/build/dxvk/build$bits" "$ROOT/upstream/dxvk-cx"
        ninja -C "$ROOT/build/dxvk/build$bits" install
    done
}

case $step in
    deps) deps ;;
    wine) wine ;;
    dxvk) dxvk ;;
    all) deps; wine; dxvk ;;
    *) echo "usage: $0 [deps|wine|dxvk|all]" >&2; exit 2 ;;
esac
