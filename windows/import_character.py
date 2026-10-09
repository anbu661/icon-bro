"""
Turns AI-generated character images/clips into Bro poses (Windows, macOS or Linux).

  python import_character.py <character-name> <folder>
  python import_character.py --find-loop walk.mp4            # best seamless walk loop (start, frames)

<folder> holds files named by pose: idle / happy / water / warn / angry / walk
  .png .jpg .webp  -> still pose
  .mp4 .mov        -> animated pose (frames extracted at 24 fps)

Backgrounds are removed with rembg; every pose is trimmed and scaled to 600 px tall. Animated poses share
one crop so the character doesn't jitter. Output goes to %APPDATA%\\Bro\\stickers\\<name>\\ on Windows and
~/Library/Application Support/DesktopBuddy/stickers/<name>/ on macOS.

Needs: pip install rembg[cpu] pillow numpy   and ffmpeg on PATH.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from rembg import new_session, remove

HEIGHT, FPS = 600, 24
STILL = {".png", ".jpg", ".jpeg", ".webp"}
VIDEO = {".mp4", ".mov", ".m4v", ".webm"}


def stickers_dir():
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/DesktopBuddy/stickers"
    return Path(os.environ.get("APPDATA", Path.home())) / "Bro" / "stickers"


def cut(img, session):
    return remove(img.convert("RGBA"), session=session)


def save(img, box, dest):
    pad = 8
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(img.width, box[2] + pad), min(img.height, box[3] + pad))
    out = img.crop(box)
    out = out.resize((round(out.width * HEIGHT / out.height), HEIGHT), Image.LANCZOS)
    out.save(dest)


def import_still(path, dest, session):
    img = cut(Image.open(path), session)
    box = img.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
    if not box:
        print(f"  ✗ no person found in {path.name}")
        return
    save(img, box, dest)
    print(f"  ✓ {dest.name}")


def import_clip(path, dest_dir, session):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf", f"fps={FPS},scale=-2:720",
                        str(Path(tmp) / "%03d.png")], check=True)
        frames = [cut(Image.open(f), session) for f in sorted(Path(tmp).glob("*.png"))]
    boxes = [f.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox() for f in frames]
    boxes = [b for b in boxes if b]
    if not boxes:
        print(f"  ✗ no person found in {path.name}")
        return
    union = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    shutil.rmtree(dest_dir, ignore_errors=True)
    dest_dir.mkdir(parents=True)
    for i, f in enumerate(frames, 1):
        save(f, union, dest_dir / f"{i:03d}.png")
    print(f"  ✓ {dest_dir.name}/ ({len(frames)} frames)")


def find_loop(video, start=0.0, length=4.0, min_frames=14):
    """Finds the two most similar frames at least min_frames apart = the cleanest walk-cycle loop."""
    w, h = 64, 86
    raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(start), "-t", str(length), "-i", str(video),
                          "-vf", f"scale={w}:{h},format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
    fr = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(float)
    best = min(((np.abs(fr[i] - fr[j]).mean(), i, j) for i in range(len(fr)) for j in range(i + min_frames, len(fr))))
    _, i, j = best
    rate = 24
    print(f"loop: start at {start + i / rate:.3f}s, {j - i} frames")
    print(f'cut it: ffmpeg -ss {start + i / rate:.3f} -i "{video}" -frames:v {j - i} -an walk.mp4')


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--find-loop":
        return find_loop(sys.argv[2])
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    name, src = sys.argv[1], Path(sys.argv[2])
    dest = stickers_dir() / name
    dest.mkdir(parents=True, exist_ok=True)
    session = new_session("isnet-general-use")
    for f in sorted(src.iterdir()):
        ext = f.suffix.lower()
        if ext in STILL:
            print(f"• {f.stem} (still)")
            import_still(f, dest / f"{f.stem}.png", session)
        elif ext in VIDEO:
            print(f"• {f.stem} (animation)")
            import_clip(f, dest / f.stem, session)
    print(f"Done → {dest}")


if __name__ == "__main__":
    main()
