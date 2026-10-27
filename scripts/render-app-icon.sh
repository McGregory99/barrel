#!/bin/sh
# Renders app/AppIcon.icns from docs/media/logos/barrel.svg with headless Chrome.
# The artwork sits on Apple's icon grid: an 824-point rounded square centred on a 1024 canvas.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/icon.html" <<HTML
<!doctype html><html><body style="margin:0;background:transparent">
<div style="width:1024px;height:1024px;display:flex;align-items:center;justify-content:center">
<img src="file://$ROOT/docs/media/logos/barrel.svg" width="824" height="824"
     style="filter:drop-shadow(0 10px 14px rgba(0,0,0,.28))">
</div></body></html>
HTML
"$CHROME" --headless=new --hide-scrollbars --disable-gpu --default-background-color=00000000 \
    --window-size=1024,1024 --user-data-dir="$WORK/profile" --screenshot="$WORK/icon.png" \
    "file://$WORK/icon.html" >/dev/null 2>&1

SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ROOT/app/AppIcon.icns"
echo "wrote app/AppIcon.icns"
