#!/bin/bash
# Turns a folder of character images/clips into a Buddy character.
#
#   ./import-character.sh <character-name> <folder>
#
# The folder can contain, named by pose:
#   idle / happy / water / warn / angry / walk   .png .jpg .jpeg .webp   -> a still pose
#   idle / happy / water / warn / angry / walk   .mp4 .mov               -> an animated pose
# Backgrounds are removed on-device with macOS Vision. Missing poses fall back to idle.
# Optional: TITLE="Captain Hydro" WALK_FACES_RIGHT=false RUN_FACES_RIGHT=false (written to character.json)
set -euo pipefail
cd "$(dirname "$0")"
NAME="$1"; SRC="$2"; FPS="${FPS:-12}"
DEST="$HOME/Library/Application Support/DesktopBuddy/stickers/$NAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$DEST"

shopt -s nullglob nocaseglob
for f in "$SRC"/*; do
  base="$(basename "$f")"; pose="${base%.*}"; ext="${base##*.}"
  case "$(echo "$ext" | tr A-Z a-z)" in
    png|jpg|jpeg|webp|heic)
      echo "• $pose (still)"
      rm -rf "$DEST/$pose" "$DEST/$pose".*
      swift tools/cutout.swift "$TMP/still" "$f" >/dev/null
      if [ -f "$TMP/still/$pose.png" ]; then mv "$TMP/still/$pose.png" "$DEST/$pose.png"
      else echo "  ✗ couldn't find a person in $base, skipped"; fi ;;
    mp4|mov|m4v)
      echo "• $pose (animation)"
      mkdir -p "$TMP/$pose"
      ffmpeg -v error -i "$f" -vf "fps=$FPS,scale=-2:720" "$TMP/$pose/%03d.png"
      rm -rf "$DEST/$pose" "$DEST/$pose".*
      swift tools/cutout.swift ${CUTOUT_MODE:---sequence} "$DEST/$pose" "$TMP/$pose"/*.png >/dev/null
      echo "  $(ls "$DEST/$pose" | wc -l | tr -d ' ') frames" ;;
  esac
done
# per-character info: display name, which way the walk/run clips face, playback speed
if [ ! -f "$DEST/character.json" ]; then
  cat > "$DEST/character.json" <<JSON
{
  "name": "${TITLE:-$NAME}",
  "walkFacesRight": ${WALK_FACES_RIGHT:-true},
  "runFacesRight": ${RUN_FACES_RIGHT:-true},
  "fps": $FPS
}
JSON
fi
echo "Done → $DEST"
echo "Right-click Buddy → Character → $NAME"
