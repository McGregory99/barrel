#!/bin/sh
# Regression check: in a throwaway bottle, runs tools/d3d11-smoke on every installed D3D backend and
# fails unless each one renders 120 frames. Uses dist/runtime when present, else the build tree.
# Usage: scripts/smoke-backends.sh [backend ...]   (default: wined3d dxvk dxmt)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/barrel-smoke.XXXXXX")
trap 'WINEPREFIX="$WORK/home/Bottles/Smoke" "$BARREL_WINE"server -k 2>/dev/null; rm -rf "$WORK"' EXIT

if [ -d "$ROOT/dist/runtime" ]; then
    R=$ROOT/dist/runtime
    export BARREL_WINE=$R/wine/bin/wine BARREL_LIBS=$R/deps/lib BARREL_DXVK=$R/dxvk BARREL_DXMT=$R/dxmt
else
    B=$ROOT/build
    export BARREL_WINE=$B/install/bin/wine BARREL_LIBS=$B/deps/lib BARREL_DXVK=$B/dxvk/install BARREL_DXMT=$B/dxmt/install
fi
export BARREL_HOME=$WORK/home WINEDEBUG=-all
barrel=$ROOT/barrel/.build/debug/barrel
[ -x "$barrel" ] || swift build --package-path "$ROOT/barrel" --product barrel >/dev/null

"$barrel" create Smoke --template win10 >/dev/null
cp "$ROOT/tools/d3d11-smoke/d3d11-smoke.exe" "$WORK/"

failed=0
for backend in ${*:-wined3d dxvk dxmt}; do
    "$barrel" graphics Smoke "$backend" >/dev/null
    rm -f "$WORK/d3d11-smoke.txt"
    (cd "$WORK" && "$barrel" run --bottle Smoke "$WORK/d3d11-smoke.exe" >/dev/null 2>&1) || true
    if grep -q '^result: OK' "$WORK/d3d11-smoke.txt" 2>/dev/null; then
        echo "ok    $backend: $(grep -E '^(adapter|frames)' "$WORK/d3d11-smoke.txt" | tr '\n' ' ')"
    else
        echo "FAIL  $backend: $(tr '\n' ' ' < "$WORK/d3d11-smoke.txt" 2>/dev/null || echo 'no result')"
        failed=1
    fi
done
exit $failed
