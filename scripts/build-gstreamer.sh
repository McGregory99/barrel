#!/bin/sh
# Builds x86_64 GLib + GStreamer (core, base, good, a few bad/ugly plugins, gst-libav with FFmpeg)
# into build/deps, for Wine's winegstreamer (Wine runs under Rosetta, so every dylib is x86_64).
# Prerequisites (Homebrew, arm64 is fine for tools): meson ninja pkg-config bison; network access
# for meson wraps (gvdb, libffi, pcre2, proxy-libintl, orc, ogg, vorbis, opus, flac) and the
# nasm/FFmpeg release tarballs (fetched into upstream/ and checked against pinned sha256).
# Sources: upstream/crossover-26.3/sources/{glib,gstreamer} (CrossOver 26.3 LGPL sources).
# Runtime: install names are absolute (build/deps/lib), and the plugin directory and
# gst-plugin-scanner paths are compiled in, so no GStreamer env var is needed in place;
# set GST_REGISTRY_1_0 so the registry cache does not land in ~/.cache/gstreamer-1.0.
# Usage: scripts/build-gstreamer.sh [glib|nasm|ffmpeg|gstreamer|wine|all]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/upstream/crossover-26.3/sources
DEPS=$ROOT/build/deps
BUILD=$ROOT/build/gstreamer
JOBS=${JOBS:-8}
export PATH=/opt/homebrew/opt/bison/bin:$PATH

step=${1:-all}

# Meson cross file: host is x86_64 macOS; Rosetta runs the test binaries, so no exe wrapper.
# The @loader_path rpaths (lib/, lib/gstreamer-1.0/, bin/) prepare for relocating build/deps.
cross_file() {
    mkdir -p "$BUILD"
    cat > "$BUILD/cross-x86_64.txt" <<EOF
[binaries]
c = ['clang', '-arch', 'x86_64']
cpp = ['clang++', '-arch', 'x86_64']
objc = ['clang', '-arch', 'x86_64']
objcpp = ['clang++', '-arch', 'x86_64']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'

[properties]
pkg_config_libdir = '$DEPS/lib/pkgconfig'
needs_exe_wrapper = false

[built-in options]
c_link_args = ['-Wl,-headerpad_max_install_names', '-Wl,-rpath,@loader_path', '-Wl,-rpath,@loader_path/..', '-Wl,-rpath,@loader_path/../lib']
cpp_link_args = ['-Wl,-headerpad_max_install_names', '-Wl,-rpath,@loader_path', '-Wl,-rpath,@loader_path/..', '-Wl,-rpath,@loader_path/../lib']
objc_link_args = ['-Wl,-headerpad_max_install_names', '-Wl,-rpath,@loader_path', '-Wl,-rpath,@loader_path/..', '-Wl,-rpath,@loader_path/../lib']

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
    # GLib 2.78's gdbus-codegen imports distutils.version (removed in Python 3.12); meson runs it
    # with its own Python, so provide a minimal LooseVersion shim on PYTHONPATH.
    mkdir -p "$BUILD/pyshim/distutils"
    : > "$BUILD/pyshim/distutils/__init__.py"
    cat > "$BUILD/pyshim/distutils/version.py" <<'EOF'
import re


class LooseVersion:
    def __init__(self, v):
        self.version = [int(p) if p.isdigit() else p for p in re.split(r"(\d+|[a-z]+|\.)", str(v)) if p and p != "."]

    def __lt__(self, other):
        return self.version < other.version

    def __eq__(self, other):
        return self.version == other.version
EOF
}
export PYTHONPATH=$BUILD/pyshim${PYTHONPATH:+:$PYTHONPATH}

# GLib 2.78 from the CX tarball; libffi, pcre2 and proxy-libintl come from its meson wraps.
glib() {
    [ -f "$DEPS/lib/pkgconfig/glib-2.0.pc" ] && return 0
    cross_file
    # The CX tarball ships subprojects/gvdb as an empty directory; remove it so meson clones the wrap.
    rmdir "$SRC/glib/subprojects/gvdb" 2>/dev/null || true
    [ -f "$BUILD/glib/build.ninja" ] ||
        meson setup --cross-file "$BUILD/cross-x86_64.txt" --prefix "$DEPS" --libdir lib --buildtype release \
            -Dtests=false -Dgtk_doc=false -Dman=false -Dnls=disabled \
            -Dselinux=disabled -Dlibmount=disabled -Dxattr=false -Dsysprof=disabled -Ddtrace=false \
            -Dlibelf=disabled \
            "$BUILD/glib" "$SRC/glib"
    meson install -C "$BUILD/glib"
}

# nasm (native arm64 build tool) so FFmpeg keeps its x86 SIMD assembly; Homebrew does not ship it here.
# Source: https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz
# (sha256 1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148).
NASM=$ROOT/build/tools/bin/nasm

# fetch URL SHA256: download a release tarball into upstream/ once and verify it.
fetch() {
    f=$ROOT/upstream/$(basename "$1")
    [ -f "$f" ] || curl -fL -o "$f" "$1"
    echo "$2  $f" | shasum -a 256 -c -
}

nasm() {
    [ -x "$NASM" ] && return 0
    # nasm's out-of-tree build does not create its object subdirectories; build in an extracted copy.
    fetch https://www.nasm.us/pub/nasm/releasebuilds/2.16.03/nasm-2.16.03.tar.xz \
        1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148
    [ -d "$BUILD/nasm-2.16.03" ] || (mkdir -p "$BUILD" && tar xf "$ROOT/upstream/nasm-2.16.03.tar.xz" -C "$BUILD")
    (cd "$BUILD/nasm-2.16.03" && ./configure --prefix="$ROOT/build/tools" && make -j"$JOBS" nasm &&
        mkdir -p "$ROOT/build/tools/bin" && cp nasm "$NASM")
}

# FFmpeg 6.1 (LGPL) for gst-libav, decoders and parsers only: the codecs games use for cutscenes
# (H.264/HEVC/MPEG/WMV/VC-1/VP*/Theora/Indeo/Cinepak video; AAC/MP3/WMA/AC-3/Vorbis/Opus/PCM/ADPCM audio).
# Source: https://ffmpeg.org/releases/ffmpeg-6.1.2.tar.xz
# (sha256 3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38).
ffmpeg() {
    [ -f "$DEPS/lib/pkgconfig/libavcodec.pc" ] && return 0
    nasm
    fetch https://ffmpeg.org/releases/ffmpeg-6.1.2.tar.xz \
        3b624649725ecdc565c903ca6643d41f33bd49239922e45c9b1442c63dca4e38
    src=$ROOT/upstream/ffmpeg-6.1.2
    [ -d "$src" ] || (cd "$ROOT/upstream" && tar xf ffmpeg-6.1.2.tar.xz)
    mkdir -p "$BUILD/ffmpeg"
    (cd "$BUILD/ffmpeg" && "$src/configure" --prefix="$DEPS" --enable-cross-compile --arch=x86_64 \
        --target-os=darwin --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" --host-cc=clang \
        --x86asmexe="$NASM" --enable-shared --disable-static --disable-programs --disable-doc \
        --disable-autodetect --disable-network --disable-everything \
        --enable-avcodec --enable-avformat --enable-avfilter --enable-avutil --enable-swresample \
        --enable-decoder='h264,hevc,mpeg1video,mpeg2video,mpeg4,h263,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,wmv3image,vc1,vc1image,vp3,vp6,vp6a,vp6f,vp8,vp9,theora,cinepak,indeo2,indeo3,indeo4,indeo5,mjpeg,flv,msvideo1,rawvideo' \
        --enable-decoder='aac,aac_latm,ac3,eac3,mp1,mp2,mp3,mp1float,mp2float,mp3float,wmav1,wmav2,wmapro,wmavoice,wmalossless,vorbis,opus,flac,alac,dca,gsm,gsm_ms,pcm_*,adpcm_*' \
        --enable-parser='h264,hevc,mpegvideo,mpeg4video,h263,vc1,vp3,vp8,vp9,aac,aac_latm,ac3,mpegaudio,opus,vorbis,flac,dca,mjpeg' \
        && make -j"$JOBS" && make install)
}

# GStreamer 1.24 monorepo from the CX tarball. Every auto feature is disabled; only the plugins
# winegstreamer needs (decodebin, converters, videoflip, deinterlace) plus common game containers,
# parsers and decoders are enabled. ogg/vorbis/opus/flac/orc come from meson wraps.
gstreamer() {
    [ -f "$DEPS/lib/pkgconfig/gstreamer-1.0.pc" ] && [ -f "$DEPS/lib/gstreamer-1.0/libgstlibav.dylib" ] && return 0
    glib
    ffmpeg
    cross_file
    on() { p=$1; shift; for o in "$@"; do printf ' -D%s:%s=enabled' "$p" "$o"; done; }
    [ -f "$BUILD/gst/build.ninja" ] ||
        # shellcheck disable=SC2046
        meson setup --cross-file "$BUILD/cross-x86_64.txt" --prefix "$DEPS" --libdir lib --buildtype release \
            -Dauto_features=disabled -Dbase=enabled -Dgood=enabled -Dugly=enabled -Dbad=enabled -Dlibav=enabled \
            -Dtools=enabled -Dorc=enabled -Dgpl=disabled -Dtests=disabled -Dexamples=disabled \
            -Dintrospection=disabled -Dnls=disabled -Ddoc=disabled \
            $(on gst-plugins-base app audioconvert audioresample audiorate playback typefind videoconvertscale \
                videorate volume pbtypes rawparse ogg vorbis opus) \
            $(on gst-plugins-good audioparsers avi deinterlace flv id3demux apetag icydemux isomp4 matroska \
                videofilter wavparse law flac) \
            $(on gst-plugins-ugly asfdemux) \
            $(on gst-plugins-bad videoparsers mpegdemux mpegtsdemux) \
            "$BUILD/gst" "$SRC/gstreamer"
    meson install -C "$BUILD/gst"
}

# Reconfigure the existing Wine build (same flags as build-engine.sh's wine step) so configure finds
# GStreamer, then build winegstreamer only. Installs just the winegstreamer files, never a full
# `make install`, so a running bottle is not disturbed.
wine() {
    cd "$ROOT/build/wine64"
    grep -q '^GSTREAMER_LIBS = .*gstreamer' Makefile 2>/dev/null ||
        PKG_CONFIG_LIBDIR=$DEPS/lib/pkgconfig arch -x86_64 "$ROOT/upstream/wine-11.0/configure" \
            --prefix="$ROOT/build/install" --enable-archs=i386,x86_64 \
            CC="clang -arch x86_64" OBJC="clang -arch x86_64" CFLAGS="-O2" \
            CPPFLAGS="-I$DEPS/include" LDFLAGS="-L$DEPS/lib -Wl,-rpath,$DEPS/lib" \
            FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype"
    arch -x86_64 make -j"$JOBS" dlls/winegstreamer/x86_64-windows/winegstreamer.dll \
        dlls/winegstreamer/i386-windows/winegstreamer.dll dlls/winegstreamer/winegstreamer.so
    lib=$ROOT/build/install/lib/wine
    for d in x86_64-windows i386-windows; do
        install -m 644 "dlls/winegstreamer/$d/winegstreamer.dll" "$lib/$d/winegstreamer.dll"
    done
    install -m 755 dlls/winegstreamer/winegstreamer.so "$lib/x86_64-unix/winegstreamer.so"
}

case $step in
    glib) glib ;;
    nasm) nasm ;;
    ffmpeg) ffmpeg ;;
    gstreamer) gstreamer ;;
    wine) wine ;;
    all) gstreamer; wine ;;
    *) echo "usage: $0 [glib|nasm|ffmpeg|gstreamer|wine|all]" >&2; exit 2 ;;
esac
