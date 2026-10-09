#!/bin/bash
# Prepares windows/stickers/ (WebP frames) and windows/bro.ico from your Mac characters, ready for build_windows.bat.
#   ./windows/pack_assets.sh                     biscuit (default) denim ironman drop buddy
#   CHARS="biscuit denim" ./windows/pack_assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
STICKERS="${STICKERS:-$HOME/Library/Application Support/DesktopBuddy/stickers}"
CHARS="${CHARS:-biscuit denim ironman drop buddy}"
OUT=windows/stickers
PY="${PYTHON:-python3}"
rm -rf "$OUT"; mkdir -p "$OUT"
for c in $CHARS; do
  echo "• $c"
  swift tools/render_png.swift "$STICKERS/$c" "$OUT/$c" 360
  [ -f "$STICKERS/$c/character.json" ] && cp "$STICKERS/$c/character.json" "$OUT/$c/"
done
"$PY" - "$OUT" "$STICKERS/${CHARS%% *}/idle.png" <<'PYEOF'
import sys
from pathlib import Path
from PIL import Image
out, icon_src = Path(sys.argv[1]), sys.argv[2]
n = 0
for png in out.rglob("*.png"):
    Image.open(png).save(png.with_suffix(".webp"), "WEBP", quality=82, method=4)
    png.unlink(); n += 1
print(f"  {n} frames -> WebP")
# square app icon from the default character's idle pose
img = Image.open(icon_src).convert("RGBA")
img = img.crop(img.getbbox())
side = max(img.size)
sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
sq.paste(img, ((side - img.width) // 2, side - img.height))
sq.save("windows/bro.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("  icon -> windows/bro.ico")
PYEOF
du -sh "$OUT"/* windows/bro.ico
