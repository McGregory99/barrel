#!/bin/sh
# Builds the Windows runtime for Apple Silicon (x86_64 under Rosetta) into build/.
# Prerequisites (Homebrew, arm64 is fine for tools): mingw-w64 bison cmake meson ninja glslang.
# Sources (git-ignored, see docs/wine-patches.md):
#   upstream/crossover-26.3/sources  CrossOver 26.3 source tarball
#   upstream/wine-11.0               Wine 11.0 + CX patches (branch cx-26.3)
#   upstream/dxvk-cx                 DXVK 1.10.3 from CX sources + mingw-w64 14 fixes
#   upstream/moltenvk-cx             MoltenVK 1.2.10 from CX sources (geometry shader emulation DXVK needs)
#   upstream/spirv-cross-cx          SPIRV-Cross copied from CX sources (fetchDependencies deletes its root)
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
    moltenvk
}

# Upstream MoltenVK lacks geometry shaders, so DXVK cannot create a device; CX's fork emulates them.
moltenvk() {
    mvk=$ROOT/upstream/moltenvk-cx
    [ -d "$ROOT/upstream/spirv-cross-cx" ] || cp -R "$SRC/moltenvk/External/SPIRV-Cross" "$ROOT/upstream/spirv-cross-cx"
    (cd "$mvk" && ./fetchDependencies --macos --spirv-cross-root "$ROOT/upstream/spirv-cross-cx" && make macos)
    mkdir -p "$DEPS/lib"
    cp "$mvk/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$DEPS/lib/"
}

# gmp → nettle → gnutls (with bundled libtasn1), all x86_64, for Wine's schannel/bcrypt.
gnutls() {
    tls=$SRC/gnutls
    mkdir -p "$ROOT/build/gmp" "$ROOT/build/nettle" "$ROOT/build/gnutls"
    [ -f "$DEPS/lib/libgmp.dylib" ] || (cd "$ROOT/build/gmp" && arch -x86_64 "$tls/gmp/configure" --prefix="$DEPS" CC="clang -arch x86_64" \
        --enable-shared --disable-static && arch -x86_64 make -j"$JOBS" && make install)
    # The CX tarball ships nettle without its hand-written Makefile.in; use the identical
    # upstream GNU release (nettle-3.10.tar.gz, sha256 b4c518ad…ee47c) instead.
    nettle=$ROOT/upstream/nettle-3.10/nettle-3.10
    (cd "$ROOT/build/nettle" && arch -x86_64 "$nettle/configure" --prefix="$DEPS" CC="clang -arch x86_64" \
        --disable-documentation --disable-static --with-include-path="$DEPS/include" --with-lib-path="$DEPS/lib" \
        && arch -x86_64 make -j"$JOBS" && make install)
    (cd "$ROOT/build/gnutls" && PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig arch -x86_64 "$tls/gnutls/configure" \
        --prefix="$DEPS" CC="clang -arch x86_64" --enable-shared --disable-static --disable-doc --disable-tests \
        --disable-tools --disable-cxx --with-included-libtasn1 --with-included-unistring --without-p11-kit \
        --without-idn --without-brotli --without-zstd --without-tpm --without-tpm2 \
        && arch -x86_64 make -j"$JOBS" && make install)
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
    moltenvk) moltenvk ;;
    gnutls) gnutls ;;
    wine) wine ;;
    dxvk) dxvk ;;
    all) deps; gnutls; wine; dxvk ;;
    *) echo "usage: $0 [deps|moltenvk|gnutls|wine|dxvk|all]" >&2; exit 2 ;;
esac
