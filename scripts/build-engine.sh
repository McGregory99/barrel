#!/bin/sh
# Builds the Windows runtime for Apple Silicon (x86_64 under Rosetta) into build/.
# Prerequisites (Homebrew, arm64 is fine for tools): mingw-w64 bison cmake meson ninja glslang.
# Sources (git-ignored, see docs/wine-patches.md):
#   upstream/crossover-26.3/sources  CrossOver 26.3 source tarball
#   upstream/wine-11.0               Wine 11.0 + CX patches (branch cx-26.3)
#   upstream/dxvk-cx                 DXVK 1.10.3 from CX sources + mingw-w64 14 fixes
#   upstream/moltenvk-cx             MoltenVK 1.2.10 from CX sources (geometry shader emulation DXVK needs)
#   upstream/spirv-cross-cx          SPIRV-Cross copied from CX sources (fetchDependencies deletes its root)
#   upstream/dxmt                    DXMT (LGPL-2.1+), git clone --recursive https://github.com/3Shain/dxmt
#   upstream/llvm-15                 llvm-project llvmorg-15.0.7 (DXMT's shader converter links LLVM 15)
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
    [ -f "$DEPS/lib/libnettle.dylib" ] || (cd "$ROOT/build/nettle" && arch -x86_64 "$nettle/configure" --prefix="$DEPS" CC="clang -arch x86_64" \
        --disable-documentation --disable-static --with-include-path="$DEPS/include" --with-lib-path="$DEPS/lib" \
        && arch -x86_64 make -j"$JOBS" && make install)
    # libtool drops absolute .dylib paths from *_LIBS when linking libgnutls, so link them via LDFLAGS.
    tls_link="-L$DEPS/lib -lhogweed -lnettle -lgmp"
    # CX's m4/hooks.m4 tests `x$NETTLE_LIBS != x` unquoted, so each *_LIBS must be one word (no spaces).
    (cd "$ROOT/build/gnutls" && PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig arch -x86_64 "$tls/gnutls/configure" \
        --prefix="$DEPS" CC="clang -arch x86_64" CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib" \
        NETTLE_CFLAGS="-I$DEPS/include" HOGWEED_CFLAGS="-I$DEPS/include" \
        NETTLE_LIBS="$DEPS/lib/libnettle.dylib" HOGWEED_LIBS="$DEPS/lib/libhogweed.dylib" \
        GMP_LIBS="$DEPS/lib/libgmp.dylib" \
        --enable-shared --disable-static --disable-doc --disable-tests \
        --disable-tools --disable-cxx --with-included-libtasn1 --with-included-unistring --without-p11-kit \
        --without-idn --without-brotli --without-zstd --without-tpm --without-tpm2 --disable-gost \
        && arch -x86_64 make -j"$JOBS" LDFLAGS="$tls_link" && make install LDFLAGS="$tls_link")
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

# LLVM 15 static libraries for x86_64 macOS (no targets, no tools): only DXMT's airconv needs them.
llvm15() {
    [ -f "$ROOT/build/llvm-15/lib/libLLVMCore.a" ] && return 0
    [ -d "$ROOT/upstream/llvm-15" ] ||
        git clone --depth 1 --branch llvmorg-15.0.7 https://github.com/llvm/llvm-project.git "$ROOT/upstream/llvm-15"
    cmake -S "$ROOT/upstream/llvm-15/llvm" -B "$ROOT/build/llvm-15-build" -G Ninja \
        -DCMAKE_INSTALL_PREFIX="$ROOT/build/llvm-15" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
        -DLLVM_HOST_TRIPLE=x86_64-apple-darwin -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=On \
        -DLLVM_ENABLE_ZSTD=Off -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_BENCHMARKS=Off \
        -DLLVM_INCLUDE_TESTS=Off -DLLVM_INCLUDE_EXAMPLES=Off \
        -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23"
    cmake --build "$ROOT/build/llvm-15-build" -j"$JOBS"
    cmake --install "$ROOT/build/llvm-15-build"
}

# DXMT: native d3d11/dxgi/d3d10core (system32, syswow64) plus the winemetal builtin bridge
# (x86_64-windows, i386-windows, x86_64-unix) that barrel puts on WINEDLLPATH.
dxmt() {
    llvm15
    for bits in 64 32; do
        llvm_arg=""
        [ "$bits" = 64 ] && llvm_arg="-Dnative_llvm_path=$ROOT/build/llvm-15"
        [ -f "$ROOT/build/dxmt/build$bits/build.ninja" ] ||
            meson setup --cross-file "$ROOT/upstream/dxmt/build-win$bits.txt" -Dwine_builtin_dll=false \
                -Dwine_install_path="$ROOT/build/install" $llvm_arg --buildtype release \
                --prefix "$ROOT/build/dxmt/install" "$ROOT/build/dxmt/build$bits" "$ROOT/upstream/dxmt"
        ninja -C "$ROOT/build/dxmt/build$bits" install
    done
}

case $step in
    deps) deps ;;
    moltenvk) moltenvk ;;
    gnutls) gnutls ;;
    wine) wine ;;
    dxvk) dxvk ;;
    llvm15) llvm15 ;;
    dxmt) dxmt ;;
    all) deps; gnutls; wine; dxvk ;;
    *) echo "usage: $0 [deps|moltenvk|gnutls|wine|dxvk|llvm15|dxmt|all]" >&2; exit 2 ;;
esac
