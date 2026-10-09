"""
Bro: a desktop companion for Windows 10/11 (share edition).

Floats on the desktop and walks around, reminds you to drink water, asks how long you want on YouTube /
Instagram / OTT sites and closes the tab when time's up, tidies folders, and chats. Offline by default;
"Agentic chat" is opt-in with your own API key (OpenAI, Anthropic, Gemini or any OpenAI-compatible service).

Run:      python bro.py
Package:  see build_windows.bat (PyInstaller, one-file Bro.exe with the characters inside)
Data:     %APPDATA%\\Bro\\  (config.json, stickers\\<character>\\, ai.key, tidy-log\\, bro.log)
"""
import ctypes
import datetime
import json
import math
import os
import queue
import random
import shutil
import sys
import threading
import time
import tkinter as tk
import traceback
import winreg
import winsound
from ctypes import wintypes
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import psutil
import requests
from PIL import Image, ImageOps, ImageTk

APP = Path(os.environ.get("APPDATA", Path.home())) / "Bro"
STICKERS = APP / "stickers"
CONFIG = APP / "config.json"
KEY_FILE = APP / "ai.key"
TIDY_LOG = APP / "tidy-log"
LOG = APP / "bro.log"
BUNDLE = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))   # PyInstaller unpack dir, or next to bro.py
CHROMA = "#00ff01"          # window colour made transparent by Windows
CHROMA_RGB = (0, 255, 1)

# Sites/OTT shown as checkboxes in Settings: (name, words matched in the browser window title)
KNOWN_SITES = [
    ("YouTube", ["youtube"]), ("Instagram", ["instagram"]), ("Facebook", ["facebook"]),
    ("X / Twitter", ["/ x", "twitter"]), ("Reddit", ["reddit"]), ("Netflix", ["netflix"]),
    ("Prime Video", ["prime video"]), ("JioHotstar", ["hotstar"]), ("JioCinema", ["jiocinema"]),
    ("SonyLIV", ["sonyliv"]), ("ZEE5", ["zee5"]), ("Disney+", ["disney+"]),
    ("aha", ["aha.video", "| aha", "aha -"]), ("Sun NXT", ["sun nxt", "sunnxt"]),
]
TIME_CHOICES = [1, 5, 10, 15, 20, 30, 45, 60, 90, 120]

DEFAULTS = {
    "userName": "Bro",
    "character": "biscuit",
    "height": 220,                       # on-screen character box height (at 100% display scaling)
    "waterIntervalMinutes": 45,
    "distractingSites": [name for name, _ in KNOWN_SITES if name not in ("Facebook", "X / Twitter", "Reddit")],
    "askBudget": True,                   # ask "how much time do you need?" when a site opens
    "budgetOptionsMinutes": [5, 15, 30, 60],
    "defaultBudgetMinutes": 15,          # used when nobody answers the question
    "nagAfterMinutes": 15,
    "closeAfterMinutes": 25,
    "warningSeconds": 60,
    "nagRepeatSeconds": 120,
    "breakResetMinutes": 10,
    "walking": True,
    "startWithWindows": False,
    "aiProvider": "off",                 # off, openai, anthropic, gemini, custom
    "aiModel": "",
    "aiBaseURL": "",
    "tutorialDone": False,
}

PROVIDERS = {
    "off": ("Off (offline commands only)", "", ""),
    "openai": ("OpenAI", "gpt-4.1-mini", "https://api.openai.com/v1"),
    "anthropic": ("Anthropic (Claude)", "claude-opus-5-5", ""),
    "gemini": ("Google Gemini", "gemini-2.5-flash", "https://generativelanguage.googleapis.com/v1beta/openai"),
    "custom": ("Other (OpenAI-compatible)", "", ""),
}

BROWSERS = {"chrome.exe", "msedge.exe", "brave.exe", "firefox.exe", "opera.exe", "vivaldi.exe", "arc.exe"}
STORE_APPS = {"applicationframehost.exe"}        # Netflix / Prime Video apps from the Microsoft Store

DENIM = {"deep": "#1a2e4f", "mid": "#2b4a7a", "faded": "#6687ba", "thread": "#e8b04b",
         "leather": "#8c5a2b", "cream": "#f7e8c9", "tee": "#e3e3e5", "copper": "#c97a3a"}

WATER_LINES = ["Hey, {}! Did you drink water?", "Water check, {}! Had a glass?", "{}, your body wants water. Did you drink?"]
NAG_LINES = ["{} on {} already. Wrap it up, bro?", "That's {} of {}. Almost time, bro.", "{} on {}! Save some fun for tomorrow."]
ANGRY_LINES = ["Time's up on {}! ({}) Closing it in {} seconds.", "{} done, bro ({}). Closing in {} seconds!"]


def log(*a):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} " + " ".join(str(x) for x in a) + "\n")
    except OSError:
        pass


def load_config():
    APP.mkdir(parents=True, exist_ok=True)
    STICKERS.mkdir(exist_ok=True)
    cfg = dict(DEFAULTS)
    if CONFIG.exists():
        try:
            cfg.update(json.loads(CONFIG.read_text(encoding="utf-8")))
        except json.JSONDecodeError:
            pass
    save_config(cfg)
    return cfg


def save_config(cfg):
    CONFIG.write_text(json.dumps(cfg, indent=2), encoding="utf-8")


def install_bundled_stickers():
    """Copies the characters shipped inside Bro.exe to %APPDATA%\\Bro\\stickers (never overwrites)."""
    src = BUNDLE / "stickers"
    if not src.is_dir():
        return
    for c in src.iterdir():
        if c.is_dir() and not (STICKERS / c.name).exists():
            shutil.copytree(c, STICKERS / c.name)


def parse_minutes(text):
    n, unit = text.split()
    return float(n) / 60 if unit == "sec" else float(n) * 60 if unit == "hr" else float(n)


def minutes_label(m):
    if m < 1:
        return f"{round(m * 60)} sec"
    if m >= 60:
        return "1 hr" if m == 60 else f"{m / 60:g} hr"
    return f"{int(m)} min"


# ---------------------------------------------------------------- Windows helpers

user32 = ctypes.windll.user32


def foreground_window():
    """(hwnd, title, process name, (left, top, right, bottom)) of the window in front."""
    hwnd = user32.GetForegroundWindow()
    n = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(n + 1)
    user32.GetWindowTextW(hwnd, buf, n + 1)
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    try:
        name = psutil.Process(pid.value).name().lower()
    except psutil.Error:
        name = ""
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return hwnd, buf.value, name, (rect.left, rect.top, rect.right, rect.bottom)


def window_rect(hwnd):
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def work_area():
    """Screen area minus the taskbar."""
    r = wintypes.RECT()
    ctypes.windll.user32.SystemParametersInfoW(0x0030, 0, ctypes.byref(r), 0)    # SPI_GETWORKAREA
    return r.left, r.top, r.right, r.bottom


def close_active_tab(hwnd):
    """Ctrl+W in the given browser window."""
    user32.SetForegroundWindow(hwnd)
    VK_CONTROL, VK_W, KEYUP = 0x11, 0x57, 0x0002
    user32.keybd_event(VK_CONTROL, 0, 0, 0)
    user32.keybd_event(VK_W, 0, 0, 0)
    user32.keybd_event(VK_W, 0, KEYUP, 0)
    user32.keybd_event(VK_CONTROL, 0, KEYUP, 0)


def close_window(hwnd):
    user32.PostMessageW(hwnd, 0x0010, 0, 0)          # WM_CLOSE


def site_in_title(cfg, title):
    t = title.lower()
    for name, words in KNOWN_SITES:
        if name in cfg["distractingSites"] and any(w in t for w in words):
            return name
    for name in cfg["distractingSites"]:                # anything typed into config.json by hand
        if name not in dict(KNOWN_SITES) and name.lower() in t:
            return name
    return None


def set_start_with_windows(on):
    path = r"Software\Microsoft\Windows\CurrentVersion\Run"
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path, 0, winreg.KEY_SET_VALUE) as k:
            if on and getattr(sys, "frozen", False):
                winreg.SetValueEx(k, "Bro", 0, winreg.REG_SZ, f'"{sys.executable}"')
            elif not on:
                try:
                    winreg.DeleteValue(k, "Bro")
                except FileNotFoundError:
                    pass
    except OSError as e:
        log("startup:", e)


# ---------------------------------------------------------------- Brain: offline commands + optional AI

def offline_brain(text):
    """Bro's handful of commands with plain pattern matching: works with no key and no internet."""
    t = f" {text.lower()} "

    def has(words):
        return any(w in t for w in words)

    if has(["undo", "put them back", "put it back", "put my files back", "revert"]):
        return "Okay bro, putting things back.", {"type": "undo_tidy"}
    if has(["tidy", "clean", "organis", "organiz", "sort", "arrange", "declutter"]):
        folder = "Downloads"
        for name in ("downloads", "desktop", "documents", "pictures", "videos", "music"):
            if name in t:
                folder = name.capitalize()
        for word in text.split():
            if ":\\" in word or word.startswith("~"):
                folder = word
        return "Let me take a look.", {"type": "tidy", "folder": folder}
    if has(["drank", "had water", "had some water", "drink done", "hydrated", "had a glass"]):
        return "Nice one, bro!", {"type": "drank_water"}
    if has(["walk", "move", "go "]) and has(["left", "right"]):
        return "On my way!", {"type": "walk", "direction": "left" if "left" in t else "right"}
    if has([" hi ", " hey ", "hello", " yo ", "sup", "how are you"]):
        return ("Hey bro! I'm running offline, so I know a few tricks: tidy a folder, undo a tidy, log water, "
                "or walk left or right. Turn on Agentic chat in my Settings for a proper conversation."), None
    return ('I\'m in offline mode, bro. Try "tidy my downloads", "undo", "I drank water" or "walk left". '
            "For real chat, right-click me > Settings > Agentic chat."), None


def system_prompt(cfg, character, water, scroll_min):
    return (
        f"You are {character}, the cheeky but caring cartoon desktop companion of {cfg['userName']}, living on their "
        "Windows screen. You remind them to drink water and kick them off YouTube, Instagram and OTT sites when "
        'they binge. Talk like a close friend: simple, warm English. Call them "bro" naturally. '
        'Never use "da", "machan", "macha", "dei" or "mate". Keep replies to 1-2 short, playful sentences. '
        "No markdown.\n"
        "You can also act on their computer. Respond ONLY with JSON:\n"
        '{"reply": string, "action": null | {"type":"tidy","folder":string} | {"type":"undo_tidy"} | '
        '{"type":"drank_water"} | {"type":"walk","direction":"left"|"right"}}\n'
        '- tidy: they want a folder cleaned/organised/sorted. folder = "Downloads", "Desktop", "Documents" or a path. '
        "Say you'll take a look; the app counts the files and asks them to confirm.\n"
        "- undo_tidy: put the last tidy back. - drank_water: they drank water. - walk: move left/right.\n"
        f"Facts: {water} glasses of water today; {scroll_min} min on distracting sites right now."
    )


def ai_key():
    try:
        k = KEY_FILE.read_text(encoding="utf-8").strip()
        return k or None
    except OSError:
        return None


def ai_configured(cfg):
    p = cfg.get("aiProvider", "off")
    return p in PROVIDERS and p != "off" and ai_key() is not None and (p != "custom" or cfg.get("aiBaseURL"))


def ai_send(cfg, system, history):
    """history: [("user"|"assistant", text)]. Returns the reply text; raises on errors."""
    p, key = cfg["aiProvider"], ai_key()
    model = cfg.get("aiModel") or PROVIDERS[p][1]
    if p == "anthropic":
        msgs = [{"role": r, "content": t} for r, t in history]
        while msgs and msgs[0]["role"] == "assistant":          # must start with the user
            msgs.pop(0)
        r = requests.post("https://api.anthropic.com/v1/messages", timeout=60, headers={
            "x-api-key": key, "anthropic-version": "2023-06-01",
            "anthropic-beta": "server-side-fallback-2026-07-01", "content-type": "application/json"},
            json={"model": model, "max_tokens": 16000, "system": system, "messages": msgs,
                  "output_config": {"effort": "low"},             # short chat replies: keep it quick
                  "fallbacks": "default"})                       # a declined request is retried on another Claude model
    else:
        base = (cfg["aiBaseURL"] if p == "custom" else PROVIDERS[p][2]).strip().rstrip("/")
        r = requests.post(base + "/chat/completions", timeout=60,
                          headers={"Authorization": f"Bearer {key}", "content-type": "application/json"},
                          json={"model": model, "temperature": 0.7,
                                "messages": [{"role": "system", "content": system}] +
                                            [{"role": r_, "content": t} for r_, t in history]})
    data = r.json() if r.content else {}
    if r.status_code != 200:
        raise RuntimeError((data.get("error") or {}).get("message") or f"HTTP {r.status_code}")
    if p == "anthropic":
        if data.get("stop_reason") == "refusal":
            raise RuntimeError("The model declined that one.")
        text = "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
    else:
        text = data["choices"][0]["message"]["content"] or ""
    if "</think>" in text:
        text = text.split("</think>", 1)[1]
    return text.strip()


def parse_brain(text):
    a, b = text.find("{"), text.rfind("}")
    if 0 <= a < b:
        try:
            obj = json.loads(text[a:b + 1])
            if isinstance(obj.get("reply"), str):
                return obj["reply"], obj.get("action")
        except json.JSONDecodeError:
            pass
    return text, None


# ---------------------------------------------------------------- Tidy

CATEGORIES = {
    "Images": {"png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "svg", "bmp", "tif", "tiff", "avif"},
    "Videos": {"mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"},
    "Audio": {"mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"},
    "Documents": {"pdf", "doc", "docx", "txt", "md", "rtf", "ppt", "pptx", "xls", "xlsx", "csv"},
    "Archives": {"zip", "rar", "7z", "tar", "gz", "tgz", "iso"},
}
NOUN = {"Images": "image", "Videos": "video", "Audio": "audio file", "Documents": "document", "Archives": "archive"}
IN_PROGRESS = {"crdownload", "download", "part", "partial", "tmp"}


def resolve_folder(name):
    home = Path.home()
    n = name.strip().lower().replace("my ", "").replace(" folder", "").strip()
    known = {"downloads": "Downloads", "download": "Downloads", "desktop": "Desktop", "documents": "Documents",
             "pictures": "Pictures", "videos": "Videos", "music": "Music"}
    p = home / known[n] if n in known else Path(os.path.expanduser(name.strip()))
    if n in ("desktop", "documents") and not p.is_dir():          # OneDrive-redirected folders
        p = home / "OneDrive" / known[n]
    return p if p.is_dir() else None


def tidy_plan(folder):
    moves, counts, taken = [], {}, set()
    for item in sorted(folder.iterdir()):
        if item.is_dir() or item.name.startswith(".") or item.name.lower() == "desktop.ini":
            continue
        ext = item.suffix.lower().lstrip(".")
        if ext in IN_PROGRESS:
            continue
        cat = next((c for c, exts in CATEGORIES.items() if ext in exts), None)
        if not cat:
            continue
        dest, n = folder / cat / item.name, 1
        while dest.exists() or str(dest) in taken:
            dest = folder / cat / f"{item.stem} ({n}){item.suffix}"
            n += 1
        taken.add(str(dest))
        moves.append((item, dest))
        counts[cat] = counts.get(cat, 0) + 1
    summary = ", ".join(f"{counts[c]} {NOUN[c]}{'' if counts[c] == 1 else 's'}" for c in CATEGORIES if c in counts)
    return {"folder": folder, "moves": moves, "summary": summary}


def tidy_apply(plan):
    done, failed = [], 0
    for src, dst in plan["moves"]:
        try:
            dst.parent.mkdir(exist_ok=True)
            shutil.move(str(src), str(dst))
            done.append([str(src), str(dst)])
        except OSError:
            failed += 1
    if done:
        TIDY_LOG.mkdir(exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
        (TIDY_LOG / f"{stamp}.json").write_text(json.dumps(done, indent=2), encoding="utf-8")
    return len(done), failed


def tidy_undo():
    logs = sorted(TIDY_LOG.glob("*.json")) if TIDY_LOG.exists() else []
    if not logs:
        return None
    moves, restored = json.loads(logs[-1].read_text(encoding="utf-8")), 0
    for src, dst in moves:
        if not Path(src).exists() and Path(dst).exists():
            shutil.move(dst, src)
            restored += 1
    for d in {Path(dst).parent for _, dst in moves}:
        if d.exists() and not any(d.iterdir()):
            d.rmdir()
    logs[-1].unlink()
    return restored


# ---------------------------------------------------------------- Characters

IMAGE_EXTS = {".png", ".webp", ".jpg", ".jpeg"}


def characters():
    return sorted(p.name for p in STICKERS.iterdir() if p.is_dir() and (any(p.glob("idle.*")) or (p / "idle").is_dir()))


def character_info(folder):
    try:
        return json.loads((STICKERS / folder / "character.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def display_name(folder):
    return character_info(folder).get("name") or folder.capitalize()


def pose_files(character, pose):
    """A pose is <pose>.png/.webp (one still) or a <pose>\\ folder of frames played in name order."""
    base = STICKERS / character
    if (base / pose).is_dir():
        return sorted(p for p in (base / pose).iterdir() if p.suffix.lower() in IMAGE_EXTS)
    return [base / f"{pose}{e}" for e in (".png", ".webp", ".jpg") if (base / f"{pose}{e}").exists()][:1]


def fit_frame(path, box_w, box_h, mirror=False):
    """Scales a frame into the box, bottom-centred, flattened onto the transparent key colour."""
    img = Image.open(path).convert("RGBA")
    s = min(box_w / img.width, box_h / img.height)
    img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
    if mirror:
        img = ImageOps.mirror(img)
    canvas = Image.new("RGB", (box_w, box_h), CHROMA_RGB)
    # Windows colour-key transparency is all-or-nothing, so the alpha edge is made hard
    alpha = img.getchannel("A").point(lambda a: 255 if a > 110 else 0)
    canvas.paste(img.convert("RGB"), ((box_w - img.width) // 2, box_h - img.height), alpha)
    return canvas


# ---------------------------------------------------------------- App

class Bro:
    POSES = ("idle", "happy", "water", "warn", "angry", "hello2", "walk", "run")

    def __init__(self):
        self.cfg = load_config()
        install_bundled_stickers()
        if self.cfg["character"] not in characters() and characters():
            self.cfg["character"] = "biscuit" if "biscuit" in characters() else characters()[0]
        self.ui = queue.Queue()                  # background threads hand work back to the Tk thread
        self.root = tk.Tk()
        self.root.title("Bro")
        self.k = self.root.winfo_fpixels("1i") / 96          # display scaling (1.0 = 100%)
        self.box_h = int(self.cfg["height"] * self.k)
        self.box_w = int(self.box_h * 1.2)
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.config(bg=CHROMA)
        self.root.attributes("-transparentcolor", CHROMA)
        self.label = tk.Label(self.root, bg=CHROMA, bd=0)
        self.label.pack()

        self.raw = {}                            # (pose, mirror) -> [PIL image]   (prepared off the UI thread)
        self.photos = {}                         # (pose, mirror) -> [PhotoImage]
        self.load_character(self.cfg["character"], wait_for_all=False)

        self.anim_job = self.move_job = self.water_job = self.bubble_job = None
        self.busy = False                        # walking / smashing
        self.minimized = False
        self.waiting_water = False
        self.water_today = 0
        self.distracted = 0.0
        self.last_distracted = 0.0
        self.last_nag = 0.0
        self.final_at = None
        self.caught_hwnd = None
        self.caught_browser = True
        self.session_budget = None               # seconds picked for this YouTube/OTT session
        self.asking_budget = False
        self.ask_token = 0
        self.history = []
        self.chat = None
        self.bubble = None
        self.bubble_size = (0, 0)
        self.pill = None
        self.settings = None
        self.tutorial_step = None

        l, t, r, b = work_area()
        self.x, self.y = r - self.box_w - int(40 * self.k), b - self.box_h
        self.place()

        self.label.bind("<ButtonPress-1>", self.on_press)
        self.label.bind("<B1-Motion>", self.on_drag)
        self.label.bind("<ButtonRelease-1>", self.on_release)
        self.label.bind("<Double-Button-1>", self.on_double)
        self.click_job = None
        self.after_double = False
        self.label.bind("<Button-3>", self.on_menu)

        self.set_mood("idle")
        if self.cfg["tutorialDone"]:
            self.root.after(600, self.say_hello)
        else:
            self.root.after(1200, self.start_tutorial)
        self.schedule_water()
        self.root.after(12000, self.maybe_wander)
        self.root.after(2000, self.poll_browser)
        self.root.after(50, self.drain)
        self.root.report_callback_exception = lambda *e: log("".join(traceback.format_exception(*e)))

    # ---- plumbing
    def later(self, fn, *a):
        self.ui.put((fn, a))

    def drain(self):
        while not self.ui.empty():
            fn, a = self.ui.get()
            fn(*a)
        self.root.after(50, self.drain)

    def sw(self):
        return work_area()

    # ---- character frames
    def load_character(self, name, wait_for_all=True):
        info = character_info(name)
        self.fps = float(info.get("fps") or 24)
        self.walk_right = bool(info.get("walkFacesRight", True))
        self.run_right = bool(info.get("runFacesRight", True))
        raw = self.raw = {}                   # a fresh dict, so an older load still running can't mix in
        self.photos = {}
        jobs = [(p, False) for p in self.POSES] + [("walk", True), ("run", True)]
        files = {p: pose_files(name, p) for p in self.POSES}
        # idle first and on this thread, so there is always something to show
        raw[("idle", False)] = [fit_frame(f, self.box_w, self.box_h) for f in files["idle"]]

        def work():
            for pose, mirror in jobs:
                if (pose, mirror) not in raw:
                    raw[(pose, mirror)] = [fit_frame(f, self.box_w, self.box_h, mirror) for f in files[pose]]
        t = threading.Thread(target=work, daemon=True)
        t.start()
        if wait_for_all:
            t.join()

    def frames(self, pose, mirror=False):
        key = (pose, mirror)
        if key not in self.photos:
            raw = self.raw.get(key)
            if raw is None:                       # still loading in the background
                return []
            self.photos[key] = [ImageTk.PhotoImage(im) for im in raw]
        return self.photos[key]

    def mood_frames(self, mood):
        return self.frames(mood) or self.frames("idle")

    def moving_frames(self, left, running=False):
        if running and self.frames("run"):
            faces_right = self.run_right
            return self.frames("run", mirror=(left == faces_right))
        faces_right = self.walk_right
        return self.frames("walk", mirror=(left == faces_right))

    # ---- animation
    def play(self, frames, loop=True, fps=None):
        if self.anim_job:
            self.root.after_cancel(self.anim_job)
            self.anim_job = None
        if not frames:
            return
        delay = max(10, int(1000 / (fps or self.fps)))

        def step(i):
            self.label.config(image=frames[i])
            if i + 1 < len(frames) or loop:
                self.anim_job = self.root.after(delay, step, (i + 1) % len(frames))
        step(0)

    def set_mood(self, mood):
        self.play(self.mood_frames(mood), loop=(mood == "idle"))

    def place(self):
        self.root.geometry(f"{self.box_w}x{self.box_h}+{int(self.x)}+{int(self.y)}")
        if self.bubble:
            self.place_bubble()

    def stop_walking(self):
        if self.move_job:
            self.root.after_cancel(self.move_job)
            self.move_job = None
        self.busy = False

    def walk(self, target_x, speed=70, done=None, running=False):
        self.stop_walking()
        l, _, r, _ = self.sw()
        target_x = max(l, min(r - self.box_w, target_x))
        left = target_x < self.x
        frames = self.moving_frames(left, running) or self.mood_frames("idle")
        self.busy = True
        if running and not self.frames("run"):
            self.play(frames, fps=self.fps * 2)              # brisk jog on the walk cycle
        else:
            self.play(frames)
        speed *= self.k

        def step():
            d = target_x - self.x
            s = speed / 60
            if abs(d) <= s:
                self.x = target_x
                self.place()
                self.busy = False
                self.move_job = None
                self.set_mood("idle")
                if done:
                    done()
                return
            self.x += s if d > 0 else -s
            self.place()
            self.move_job = self.root.after(16, step)
        step()

    def hop(self, a, b, arc, duration, done):
        start = time.time()

        def step():
            k = min(1.0, (time.time() - start) / duration)
            self.x = a[0] + (b[0] - a[0]) * k
            self.y = a[1] + (b[1] - a[1]) * k - arc * 4 * k * (1 - k)   # screen y grows downward
            self.place()
            if k < 1:
                self.root.after(16, step)
            else:
                done()
        step()

    def maybe_wander(self):
        if (self.cfg["walking"] and not self.busy and not self.minimized and not self.waiting_water
                and self.final_at is None and not self.asking_budget and self.tutorial_step is None
                and not (self.chat and self.chat.winfo_exists()) and random.random() < 0.5):
            l, _, r, _ = self.sw()
            self.walk(random.randint(l, r - self.box_w))
        self.root.after(12000, self.maybe_wander)

    def say_hello(self):
        self.say(f"Hey, {self.cfg['userName']}!", 4)
        self.swag()

    # ---- effects: smoke poof + sparkles, drawn on a throwaway transparent window
    def poof(self, cx, cy, size=1.0):
        r = int(110 * self.k * size)
        w = tk.Toplevel(self.root)
        w.overrideredirect(True)
        w.attributes("-topmost", True)
        w.config(bg=CHROMA)
        w.attributes("-transparentcolor", CHROMA)
        w.geometry(f"{2 * r}x{2 * r}+{int(cx - r)}+{int(cy - r)}")
        c = tk.Canvas(w, width=2 * r, height=2 * r, bg=CHROMA, highlightthickness=0)
        c.pack()
        puffs = [(random.uniform(0, 2 * math.pi), random.uniform(0.3, 0.75), random.choice(["#ffffff", "#f1f1f1", "#dfe6ee"]))
                 for _ in range(10)]
        sparks = [(random.uniform(0, 2 * math.pi), random.uniform(0.5, 0.95)) for _ in range(8)]
        start = time.time()

        def frame():
            t = min(1.0, (time.time() - start) / 0.45)
            c.delete("all")
            for ang, dist, col in puffs:
                d = r * dist * t
                rad = r * 0.28 * (1 - t * 0.6)
                x, y = r + math.cos(ang) * d, r + math.sin(ang) * d
                c.create_oval(x - rad, y - rad, x + rad, y + rad, fill=col, outline="#c8d2dc")
            for ang, dist in sparks:
                d = r * dist * t
                x, y = r + math.cos(ang) * d, r + math.sin(ang) * d
                s = 7 * self.k * (1 - t)
                c.create_polygon(x, y - 2 * s, x + s / 2, y - s / 2, x + 2 * s, y, x + s / 2, y + s / 2,
                                 x, y + 2 * s, x - s / 2, y + s / 2, x - 2 * s, y, x - s / 2, y - s / 2,
                                 fill="#ffd659", outline="")
            if t < 1:
                w.after(16, frame)
            else:
                w.destroy()
        frame()

    def burst(self, at):
        self.poof(at[0], at[1], 0.8)

    # ---- mouse
    def on_press(self, e):
        self.drag = (e.x_root, e.y_root, self.x, self.y)
        self.moved = False

    def on_drag(self, e):
        dx, dy = e.x_root - self.drag[0], e.y_root - self.drag[1]
        if abs(dx) + abs(dy) > 3:
            self.moved = True
            self.stop_walking()
        self.x, self.y = self.drag[2] + dx, self.drag[3] + dy
        self.place()

    def on_release(self, e):
        if self.moved:
            return
        if self.after_double:                    # release of the second click of a double click
            self.after_double = False
            return
        if self.click_job:
            return
        self.click_job = self.root.after(300, self.single_click)   # wait to see whether a second click is coming

    def single_click(self):
        self.click_job = None
        self.drank() if self.waiting_water else self.swag()

    def on_double(self, e):
        if self.click_job:
            self.root.after_cancel(self.click_job)
            self.click_job = None
        self.after_double = True
        self.toggle_chat()

    def swag(self):
        """Single-click trick: the hello2 swag move once, then back to standing."""
        clip = self.frames("hello2")
        if not clip or self.busy:
            return self.set_mood("happy")
        self.play(clip, loop=False)
        self.root.after(int(len(clip) * 1000 / self.fps) + 200,
                        lambda: None if self.busy or self.waiting_water else self.set_mood("idle"))

    def build_menu(self):
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Chat with Bro", command=self.toggle_chat)
        m.add_command(label="Clear chat", command=self.clear_chat)
        chars = tk.Menu(m, tearoff=0)
        self.char_var = tk.StringVar(value=self.cfg["character"])
        for c in characters():
            chars.add_radiobutton(label=display_name(c), value=c, variable=self.char_var,
                                  command=lambda c=c: self.switch_character(c))
        m.add_cascade(label="Character", menu=chars)
        tidy = tk.Menu(m, tearoff=0)
        tidy.add_command(label="Downloads", command=lambda: self.tidy_with_confirm(resolve_folder("downloads")))
        tidy.add_command(label="Desktop", command=lambda: self.tidy_with_confirm(resolve_folder("desktop")))
        tidy.add_command(label="Choose a folder...", command=self.tidy_choose)
        tidy.add_separator()
        tidy.add_command(label="Undo last tidy", command=self.undo_tidy)
        m.add_cascade(label="Tidy a folder", menu=tidy)
        m.add_separator()
        m.add_command(label="I drank water", command=self.drank)
        m.add_command(label="Remind me to drink now", command=self.water_reminder)
        m.add_command(label="Practice smash", command=lambda: self.smash(practice=True))
        m.add_separator()
        m.add_command(label="Hide Bro", command=self.minimize)
        m.add_command(label="Settings...", command=self.open_settings)
        m.add_command(label="Show tutorial", command=self.start_tutorial)
        m.add_separator()
        m.add_command(label="Quit Bro", command=self.root.destroy)
        return m

    def on_menu(self, e):
        self.build_menu().tk_popup(e.x_root, e.y_root)

    def switch_character(self, folder):
        self.cfg["character"] = folder
        save_config(self.cfg)
        self.load_character(folder)
        if self.chat and self.chat.winfo_exists():
            self.chat.title(display_name(folder))
        self.set_mood("idle")
        self.say(f"Hey, {self.cfg['userName']}! I'm {display_name(folder)} now.", 4)
        self.root.after(200, self.swag)

    # ---- speech bubble (outlined yellow text + optional pill buttons)
    def hide_bubble(self):
        if self.bubble_job:
            self.root.after_cancel(self.bubble_job)
            self.bubble_job = None
        if self.bubble:
            self.bubble.destroy()
            self.bubble = None

    def say(self, text, seconds=8, buttons=()):
        self.hide_bubble()
        if self.minimized:
            return
        k = self.k
        width = int(max(330, 150 * len(buttons)) * k)
        b = tk.Toplevel(self.root)
        b.overrideredirect(True)
        b.attributes("-topmost", True)
        b.config(bg=CHROMA)
        b.attributes("-transparentcolor", CHROMA)
        c = tk.Canvas(b, width=width, height=10, bg=CHROMA, highlightthickness=0)
        c.pack()
        font = ("Segoe UI Black", 13)
        o = max(1, round(2 * k))
        for dx, dy in [(-o, 0), (o, 0), (0, -o), (0, o), (-o, -o), (o, o), (-o, o), (o, -o)]:
            c.create_text(width / 2 + dx, 6 * k + dy, text=text, fill="#b81414", font=font,
                          width=width - 20 * k, justify="center", anchor="n")
        c.create_text(width / 2, 6 * k, text=text, fill="#ffdb1a", font=font,
                      width=width - 20 * k, justify="center", anchor="n")
        x0, y0, x1, y1 = c.bbox("all")
        c.config(height=y1 + int(6 * k))
        if buttons:
            row = tk.Frame(b, bg=CHROMA)
            row.pack(pady=(0, int(6 * k)))
            for title, fn in buttons:
                tk.Button(row, text=title, command=fn, relief="flat", bg="white", fg="black", activebackground="#ffe680",
                          font=("Segoe UI Semibold", 10), padx=12, pady=3, bd=0, cursor="hand2").pack(side="left", padx=5)
        b.update_idletasks()
        self.bubble = b
        self.bubble_size = (b.winfo_reqwidth(), b.winfo_reqheight())
        self.place_bubble()
        if seconds:
            self.bubble_job = self.root.after(int(seconds * 1000), self.hide_bubble)

    def place_bubble(self):
        bw, bh = self.bubble_size
        l, t, r, _ = self.sw()
        x = max(l, min(r - bw, int(self.x + self.box_w / 2 - bw / 2)))
        y = max(t, int(self.y - bh + 12 * self.k))
        self.bubble.geometry(f"+{x}+{y}")

    # ---- hide to a little pill (bottom-right) and come back
    def minimize(self, quiet=False):
        if self.minimized:
            return
        self.stop_walking()
        self.hide_bubble()
        self.poof(self.x + self.box_w / 2, self.y + self.box_h / 2)
        self.minimized = True
        self.root.withdraw()
        self.show_pill()

    def restore(self, then=None):
        if not self.minimized:
            if then:
                then()
            return
        self.minimized = False
        if self.pill:
            self.pill.destroy()
            self.pill = None
        self.root.deiconify()
        self.root.attributes("-topmost", True)
        self.place()
        self.poof(self.x + self.box_w / 2, self.y + self.box_h / 2, 0.8)
        self.set_mood("idle")
        if then:
            self.root.after(350, then)

    def show_pill(self):
        p = tk.Toplevel(self.root)
        p.overrideredirect(True)
        p.attributes("-topmost", True)
        p.config(bg=DENIM["thread"])
        lbl = tk.Label(p, text="", bg=DENIM["mid"], fg=DENIM["cream"], font=("Segoe UI Semibold", 10),
                       padx=12, pady=4, cursor="hand2")
        lbl.pack(padx=2, pady=2)
        lbl.bind("<Button-1>", lambda e: self.restore())
        lbl.bind("<Button-3>", lambda e: self.build_menu().tk_popup(e.x_root, e.y_root))
        self.pill, self.pill_label = p, lbl
        self.update_pill()

    def update_pill(self):
        if not self.pill:
            return
        if self.session_budget is not None:
            left = max(0, int(self.session_budget - self.distracted))
            text = f"Bro  {left // 60}:{left % 60:02d}"
        else:
            text = "Bro  (click to show)"
        self.pill_label.config(text=text)
        self.pill.update_idletasks()
        l, t, r, b = self.sw()
        self.pill.geometry(f"+{r - self.pill.winfo_reqwidth() - int(16 * self.k)}+{b - self.pill.winfo_reqheight() - int(12 * self.k)}")

    # ---- tutorial
    def tutorial_steps(self):
        others = [display_name(c) for c in characters() if c != self.cfg["character"]]
        steps = [
            f"Hey {self.cfg['userName']}! I'm {display_name(self.cfg['character'])}, your desktop buddy!",
            "Double-click me to chat. Single-click for my swag move. Drag me anywhere you like.",
            "I can tidy your Downloads, your Desktop, or any folder you pick. Right-click me > Tidy a folder, "
            "or just tell me in chat.",
            "I watch YouTube, Instagram and OTT sites. When you open one, I'll ask how much time you need, "
            "then hide, and close it when time's up.",
            "When I hide, click the little Bro pill at the bottom-right of your screen to bring me back.",
        ]
        if others:
            steps.append(f"Want a different buddy? Right-click me > Character and pick {', '.join(others)}. "
                         "You can also change it in Settings.")
        steps += [
            f"I'll remind you to drink water every {int(self.cfg['waterIntervalMinutes'])} minutes.",
            "Change anything in Settings: right-click me > Settings. Want real AI chat? Add your API key there. Let's go!",
        ]
        return steps

    def start_tutorial(self):
        if self.minimized:
            return self.restore(self.start_tutorial)
        self.stop_walking()
        self.tutorial_step = 0
        self.show_tutorial_step()

    def show_tutorial_step(self):
        steps = self.tutorial_steps()
        i = self.tutorial_step
        last = i == len(steps) - 1
        self.set_mood("happy" if i == 0 else "idle")
        if i == 0:
            self.swag()
        buttons = [("Got it" if last else "Next >", self.next_tutorial_step)]
        if last:
            buttons.insert(0, ("Open Settings", lambda: (self.finish_tutorial(), self.open_settings())))
        else:
            buttons.append(("Skip", self.finish_tutorial))
        self.say(f"{steps[i]}  ({i + 1}/{len(steps)})", None, buttons)

    def next_tutorial_step(self):
        self.tutorial_step += 1
        if self.tutorial_step >= len(self.tutorial_steps()):
            self.finish_tutorial()
        else:
            self.show_tutorial_step()

    def finish_tutorial(self):
        self.tutorial_step = None
        self.cfg["tutorialDone"] = True
        save_config(self.cfg)
        self.hide_bubble()
        self.set_mood("idle")

    # ---- water
    def schedule_water(self):
        if self.water_job:
            self.root.after_cancel(self.water_job)
        self.water_job = self.root.after(int(self.cfg["waterIntervalMinutes"] * 60000), self.water_tick)

    def water_tick(self):
        self.water_reminder()
        self.schedule_water()

    def water_reminder(self):
        if self.minimized:
            return self.restore(self.water_reminder)
        if self.final_at or self.asking_budget or self.tutorial_step is not None:
            return self.root.after(60000, self.water_reminder)
        self.stop_walking()
        self.waiting_water = True
        self.set_mood("water")
        winsound.MessageBeep(winsound.MB_ICONASTERISK)
        self.say(random.choice(WATER_LINES).format(self.cfg["userName"]), None,
                 buttons=[("YES", self.drank), ("Remind me later", self.snooze)])

    def drank(self):
        self.waiting_water = False
        self.water_today += 1
        self.set_mood("happy")
        self.say(f"Nice! That's {self.water_today} today.", 2.5)      # cheer first...
        if not (self.chat and self.chat.winfo_exists()) and not self.minimized:
            l, _, r, _ = self.sw()
            target = l + 40 if self.x > (l + r) / 2 else r - self.box_w - 40
            self.root.after(2650, lambda: self.walk(target, speed=420, running=True))     # ...then run, text gone

    def snooze(self):
        self.waiting_water = False
        self.set_mood("warn")     # sad face
        self.say("Okay bro... 10 more minutes. Don't forget me", 6)
        self.root.after(600000, self.water_reminder)

    # ---- browser watch
    def poll_browser(self):
        poll = 2.0
        now = time.time()
        try:
            if self.final_at and now >= self.final_at:
                self.final_at = None
                self.smash()
            elif not self.busy and self.tutorial_step is None:
                hwnd, title, proc, _ = foreground_window()
                site = site_in_title(self.cfg, title) if proc in BROWSERS | STORE_APPS else None
                if site:
                    self.watch(site, hwnd, proc in BROWSERS, now, poll)
                elif self.final_at is None and now - self.last_distracted >= self.cfg["breakResetMinutes"] * 60:
                    self.distracted = 0
                    self.last_nag = 0
                    self.session_budget = None              # next visit asks again
                    self.update_pill()
        except Exception:
            log(traceback.format_exc())
        finally:
            self.root.after(int(poll * 1000), self.poll_browser)

    def watch(self, site, hwnd, is_browser, now, poll):
        self.caught_hwnd, self.caught_browser = hwnd, is_browser
        self.last_distracted = now
        if self.cfg["askBudget"] and self.session_budget is None:
            if not self.asking_budget:
                self.ask_budget(site)
            return                                       # the clock starts once they've answered
        self.distracted += poll
        self.update_pill()
        spent = f"{int(self.distracted)} sec" if self.distracted < 60 else f"{int(self.distracted // 60)} min"
        budget = self.session_budget if self.session_budget is not None else self.cfg["closeAfterMinutes"] * 60
        warning = self.cfg["warningSeconds"] if self.session_budget is None else min(self.cfg["warningSeconds"], budget / 3)
        nag_at = self.cfg["nagAfterMinutes"] * 60 if self.session_budget is None else budget / 3
        nag_every = self.cfg["nagRepeatSeconds"] if self.session_budget is None else max(5, budget / 6)
        if self.final_at is None and self.distracted >= budget - warning:
            self.final_at = now + warning

            def warn():
                self.set_mood("angry")
                winsound.MessageBeep(winsound.MB_ICONHAND)
                self.say(random.choice(ANGRY_LINES).format(site, spent, int(warning)), warning)
            self.restore(warn)
        elif (self.final_at is None and self.distracted >= nag_at
              and (self.last_nag == 0 or self.distracted - self.last_nag >= nag_every)):
            self.last_nag = self.distracted

            def nag():
                self.set_mood("warn")
                winsound.MessageBeep(winsound.MB_OK)
                self.say(random.choice(NAG_LINES).format(spent, site), 10)
            self.restore(nag)

    def ask_budget(self, site):
        """Pops up (even when hidden) and asks how long; the default is used if nobody answers."""
        self.asking_budget = True
        self.restore(lambda: self.present_budget_question(site))

    def present_budget_question(self, site):
        self.stop_walking()
        self.set_mood("idle")
        options = sorted(self.cfg["budgetOptionsMinutes"]) or [self.cfg["closeAfterMinutes"]]
        fallback = self.cfg.get("defaultBudgetMinutes") or options[0]
        if fallback not in options:
            options = sorted(options + [fallback])
        self.say(f"Hey {self.cfg['userName']}! How much time do you need on {site}?", None,
                 [(minutes_label(m), lambda m=m: self.set_budget(m)) for m in options])
        winsound.MessageBeep(winsound.MB_ICONASTERISK)
        self.ask_token += 1
        token = self.ask_token
        self.root.after(20000, lambda: self.set_budget(fallback, auto=True)
                        if self.asking_budget and self.ask_token == token else None)

    def set_budget(self, minutes, auto=False):
        self.asking_budget = False
        self.ask_token += 1
        self.session_budget = minutes * 60
        self.distracted = 0
        self.last_nag = 0
        if auto:
            self.say(f"No answer? {minutes_label(minutes)} it is.", 2)
        else:
            self.hide_bubble()                           # picked a time: the question vanishes straight away
        # then Bro gets out of the way until it's time to nag
        self.root.after(2000 if auto else 0,
                        lambda: self.minimize(quiet=True) if self.session_budget is not None and self.final_at is None else None)

    def smash(self, practice=False):
        """Leap to the browser's tab strip, smash, close the tab(s), hop back."""
        def go():
            hwnd = foreground_window()[0] if practice else self.caught_hwnd
            try:
                left, top, right, _ = window_rect(hwnd)
                tab = (left + int(220 * self.k), top + int(18 * self.k))       # roughly the first tabs in the strip
            except Exception:
                tab = (self.root.winfo_screenwidth() // 2, 20)
            home = (self.x, self.y)
            target = (tab[0] - self.box_w / 2, tab[1] - self.box_h * 0.35)
            self.stop_walking()
            self.busy = True
            self.hide_bubble()
            leap = self.moving_frames(target[0] < self.x)
            self.play([leap[8 % len(leap)]] if leap else self.mood_frames("idle"))

            def land():
                self.busy = False
                self.set_mood("angry")
                self.say("Closed. Go stretch, drink some water, look at something far away.", 8)

            def impact():
                self.play(self.mood_frames("angry"), loop=False)
                self.burst(tab)
                winsound.MessageBeep(winsound.MB_ICONEXCLAMATION)
                if not practice and hwnd:
                    browser = self.caught_browser

                    def close_loop():         # off the UI thread so Bro never freezes mid-air
                        if not browser:
                            return close_window(hwnd)
                        for i in range(8):    # keep closing while the active tab is still a distracting one
                            if i and not site_in_title(self.cfg, foreground_window()[1]):
                                break
                            close_active_tab(hwnd)
                            time.sleep(0.15)
                    threading.Thread(target=close_loop, daemon=True).start()
                    self.distracted = 0
                    self.last_nag = 0
                    self.session_budget = None
                self.root.after(500, lambda: self.hop(target, home, 70 * self.k, 0.8, land))
            self.hop(home, target, 140 * self.k, 0.85, impact)
        self.restore(go)

    # ---- tidy (no AI involved: pure file moves, always confirmed, always undoable)
    def tidy_choose(self):
        path = filedialog.askdirectory(title="Pick a folder for Bro to tidy")
        if path:
            self.tidy_with_confirm(Path(path))

    def tidy_with_confirm(self, folder):
        if not folder:
            return self.speak("I couldn't find that folder.", "warn")
        try:
            plan = tidy_plan(folder)
        except OSError:
            return self.speak(f"Windows won't let me look in {folder.name}.", "warn")
        if not plan["moves"]:
            return self.speak(f"{folder.name} is already tidy!")
        ok = messagebox.askyesno(
            f"Tidy {folder.name}?",
            f"Bro found {plan['summary']}.\n\nThey'll be moved into Images, Videos, Audio, Documents and Archives "
            f"folders inside {folder.name}. Nothing is deleted, and you can undo it from Bro's menu.")
        if not ok:
            return self.speak("Okay, I won't touch anything.")
        moved, failed = tidy_apply(plan)
        self.speak(f"Moved {moved} files into folders" + (f" ({failed} wouldn't budge)" if failed else "") +
                   ". Undo is in my menu.", "happy")
        os.startfile(plan["folder"])

    def undo_tidy(self):
        n = tidy_undo()
        self.speak(f"Done, {n} files are back where they were." if n is not None else "There's no tidy for me to undo.",
                   "happy" if n else "idle")

    # ---- settings window
    def open_settings(self):
        if self.settings and self.settings.winfo_exists():
            self.settings.lift()
            return
        SettingsWindow(self)

    def apply_settings(self, new, key_text, key_changed):
        old_char = self.cfg["character"]
        self.cfg.update(new)
        save_config(self.cfg)
        if key_changed:
            if key_text:
                KEY_FILE.write_text(key_text, encoding="utf-8")
            elif KEY_FILE.exists():
                KEY_FILE.unlink()
        set_start_with_windows(self.cfg["startWithWindows"])
        self.schedule_water()
        if self.cfg["character"] != old_char:
            self.switch_character(self.cfg["character"])
        else:
            self.say("Saved!", 2)

    # ---- chat
    def greeting(self):
        if ai_configured(self.cfg):
            return f"Hey {self.cfg['userName']}! Ask me anything, or say \"tidy my downloads\"."
        return (f"Hey {self.cfg['userName']}! I'm offline right now: try \"tidy my downloads\", \"undo\", "
                "\"I drank water\" or \"walk left\". Add an API key in Settings > Agentic chat for real chat.")

    def toggle_chat(self):
        if self.chat and self.chat.winfo_exists():
            self.chat.destroy()
            self.chat = None
            return
        c = tk.Toplevel(self.root)
        c.title(display_name(self.cfg["character"]))
        c.attributes("-topmost", True)
        c.configure(bg=DENIM["mid"], highlightbackground=DENIM["thread"], highlightthickness=2)
        w, h = int(340 * self.k), int(470 * self.k)
        c.geometry(f"{w}x{h}+{max(0, int(self.x) - w + 40)}+{max(0, int(self.y) - h // 2)}")
        head = tk.Frame(c, bg=DENIM["mid"])
        head.pack(fill="x", padx=14, pady=(12, 4))
        tk.Label(head, text=f" {display_name(self.cfg['character']).upper()} ", bg=DENIM["leather"], fg=DENIM["cream"],
                 font=("Segoe UI Black", 12), relief="ridge", bd=2).pack(side="left")
        self.status = tk.Label(head, text="● online" if ai_configured(self.cfg) else "● offline mode",
                               bg=DENIM["mid"], fg="#7CFC9A", font=("Segoe UI Semibold", 9))
        self.status.pack(side="left", padx=10)
        tk.Button(head, text="Clear", command=self.clear_chat, bg=DENIM["mid"], fg="white", relief="flat",
                  font=("Segoe UI Semibold", 9), cursor="hand2", activebackground=DENIM["faded"]).pack(side="right")
        tk.Frame(c, height=2, bg=DENIM["thread"]).pack(fill="x", padx=10, pady=6)

        bar = tk.Frame(c, bg=DENIM["mid"])
        bar.pack(side="bottom", fill="x", padx=12, pady=12)
        self.entry = tk.Entry(bar, bg="#3c5b8c", fg="white", insertbackground="white", relief="flat",
                              font=("Segoe UI", 11))
        self.entry.pack(side="left", fill="x", expand=True, ipady=8)
        self.entry.bind("<Return>", lambda e: self.send_typed())
        tk.Button(bar, text="Send", command=self.send_typed, bg=DENIM["copper"], fg="white", relief="flat",
                  font=("Segoe UI Semibold", 10), padx=10, cursor="hand2").pack(side="right", padx=(8, 0), ipady=4)

        self.log = tk.Text(c, bg=DENIM["deep"], fg="white", wrap="word", relief="flat", font=("Segoe UI", 10),
                           padx=10, pady=8, state="disabled")
        self.log.tag_config("bro", foreground="white", background=DENIM["faded"], lmargin1=4, lmargin2=4,
                            rmargin=60, spacing3=8)
        self.log.tag_config("me", foreground="#222", background=DENIM["tee"], lmargin1=60, lmargin2=60,
                            justify="right", spacing3=8)
        self.log.pack(fill="both", expand=True, padx=12)
        c.protocol("WM_DELETE_WINDOW", self.toggle_chat)
        self.chat = c
        self.add("bro", self.greeting())
        self.entry.focus_set()

    def clear_chat(self):
        """Fresh start: no messages, no memory."""
        self.history.clear()
        if self.chat and self.chat.winfo_exists():
            self.log.config(state="normal")
            self.log.delete("1.0", "end")
            self.log.config(state="disabled")
            self.add("bro", self.greeting())

    def add(self, who, text):
        if not (self.chat and self.chat.winfo_exists()):
            return
        self.log.config(state="normal")
        self.log.insert("end", f" {text} \n", who)
        self.log.config(state="disabled")
        self.log.see("end")

    def send_typed(self):
        t = self.entry.get().strip()
        self.entry.delete(0, "end")
        if t:
            self.user_said(t)

    def speak(self, text, mood="idle"):
        """Bro answers: in the chat when it's open, otherwise in a bubble."""
        if self.chat and self.chat.winfo_exists():
            self.add("bro", text)
        else:
            self.restore(lambda: self.say(text, 8))
        self.set_mood(mood)
        self.history.append(("assistant", text))

    def user_said(self, text):
        self.add("me", text)
        self.history.append(("user", text))
        if not ai_configured(self.cfg):
            return self.handle(*offline_brain(text))
        sysmsg = system_prompt(self.cfg, display_name(self.cfg["character"]), self.water_today,
                               int(self.distracted // 60))
        self.status.config(text="● thinking...", fg="#ffd27a")
        history = list(self.history[-12:])

        def work():
            try:
                reply, action = parse_brain(ai_send(self.cfg, sysmsg, history))
            except Exception as e:
                log("ai:", e)
                reply, action = offline_brain(text)
                reply = f"(AI chat problem: {e}) " + reply
            self.later(self.handle, reply, action)
        threading.Thread(target=work, daemon=True).start()

    def handle(self, reply, action):
        if self.chat and self.chat.winfo_exists():
            self.status.config(text="● online" if ai_configured(self.cfg) else "● offline mode", fg="#7CFC9A")
        kind = (action or {}).get("type")
        if kind == "tidy":
            self.speak(reply)
            self.tidy_with_confirm(resolve_folder(action.get("folder") or "Downloads"))
        elif kind == "undo_tidy":
            self.undo_tidy()
        elif kind == "drank_water":
            self.waiting_water = False
            self.water_today += 1
            self.speak(f"{reply} That's {self.water_today} today.", "happy")
        elif kind == "walk":
            self.speak(reply)
            self.walk(self.x + (-400 if action.get("direction") == "left" else 400) * self.k)
        else:
            self.speak(reply)

    def run(self):
        self.root.mainloop()


class SettingsWindow:
    """Everything people would otherwise edit in config.json."""

    def __init__(self, app):
        self.app = app
        cfg = app.cfg
        w = tk.Toplevel(app.root)
        app.settings = w
        w.title("Bro Settings")
        w.attributes("-topmost", True)
        w.resizable(False, False)
        nb = ttk.Notebook(w)
        nb.pack(fill="both", expand=True, padx=12, pady=12)
        pad = {"padx": 10, "pady": 6, "sticky": "w"}

        # You
        you = ttk.Frame(nb, padding=10)
        nb.add(you, text="You")
        ttk.Label(you, text="Bro calls you").grid(row=0, column=0, **pad)
        self.name = tk.StringVar(value=cfg["userName"])
        ttk.Entry(you, textvariable=self.name, width=28).grid(row=0, column=1, **pad)
        ttk.Label(you, text="Character").grid(row=1, column=0, **pad)
        self.char_folders = characters()
        self.character = ttk.Combobox(you, state="readonly", width=26, values=[display_name(c) for c in self.char_folders])
        if cfg["character"] in self.char_folders:
            self.character.current(self.char_folders.index(cfg["character"]))
        self.character.grid(row=1, column=1, **pad)
        self.walking = tk.BooleanVar(value=cfg["walking"])
        ttk.Checkbutton(you, text="Walk around the screen when idle", variable=self.walking).grid(row=2, column=0, columnspan=2, **pad)
        self.startup = tk.BooleanVar(value=cfg["startWithWindows"])
        ttk.Checkbutton(you, text="Start Bro when Windows starts", variable=self.startup).grid(row=3, column=0, columnspan=2, **pad)
        ttk.Label(you, text="Water reminder every").grid(row=4, column=0, **pad)
        self.water = ttk.Combobox(you, state="readonly", width=12, values=[f"{m} min" for m in (15, 20, 30, 45, 60, 90, 120)])
        self.water.set(f"{int(cfg['waterIntervalMinutes'])} min")
        self.water.grid(row=4, column=1, **pad)

        # Sites & OTT
        sites = ttk.Frame(nb, padding=10)
        nb.add(sites, text="Sites & OTT")
        ttk.Label(sites, text="Bro keeps an eye on these (matched in the browser tab title):").grid(row=0, column=0, columnspan=3, **pad)
        self.site_vars = {}
        for i, (name, _) in enumerate(KNOWN_SITES):
            v = tk.BooleanVar(value=name in cfg["distractingSites"])
            self.site_vars[name] = v
            ttk.Checkbutton(sites, text=name, variable=v).grid(row=1 + i // 3, column=i % 3, padx=10, pady=3, sticky="w")

        # Screen time
        st = ttk.Frame(nb, padding=10)
        nb.add(st, text="Screen time")
        self.ask = tk.BooleanVar(value=cfg["askBudget"])
        ttk.Checkbutton(st, text='Ask "how much time do you need?" when a site opens', variable=self.ask).grid(row=0, column=0, columnspan=5, **pad)
        ttk.Label(st, text="Time choices:").grid(row=1, column=0, columnspan=5, **pad)
        self.choice_vars = {}
        for i, m in enumerate(TIME_CHOICES):
            v = tk.BooleanVar(value=m in cfg["budgetOptionsMinutes"])
            self.choice_vars[m] = v
            ttk.Checkbutton(st, text=minutes_label(m), variable=v).grid(row=2 + i // 5, column=i % 5, padx=8, pady=3, sticky="w")
        ttk.Label(st, text="If nobody answers, use").grid(row=4, column=0, columnspan=2, **pad)
        self.default = ttk.Combobox(st, state="readonly", width=10, values=[minutes_label(m) for m in TIME_CHOICES])
        d = cfg.get("defaultBudgetMinutes") or 15
        self.default.set(minutes_label(d))
        self.default.grid(row=4, column=2, columnspan=2, **pad)
        ttk.Label(st, text="Without a chosen time, close after").grid(row=5, column=0, columnspan=2, **pad)
        self.close_after = ttk.Combobox(st, state="readonly", width=10, values=[minutes_label(m) for m in TIME_CHOICES])
        self.close_after.set(minutes_label(cfg["closeAfterMinutes"]))
        self.close_after.grid(row=5, column=2, columnspan=2, **pad)

        # Agentic chat
        ai = ttk.Frame(nb, padding=10)
        nb.add(ai, text="Agentic chat")
        ttk.Label(ai, text="Optional: real AI chat with your own API key. Without it, Bro still tidies,\n"
                           "tracks water and understands simple commands offline.").grid(row=0, column=0, columnspan=2, **pad)
        ttk.Label(ai, text="Provider").grid(row=1, column=0, **pad)
        self.provider_keys = list(PROVIDERS)
        self.provider = ttk.Combobox(ai, state="readonly", width=30, values=[PROVIDERS[p][0] for p in self.provider_keys])
        self.provider.current(self.provider_keys.index(cfg["aiProvider"]) if cfg["aiProvider"] in PROVIDERS else 0)
        self.provider.grid(row=1, column=1, **pad)
        self.provider.bind("<<ComboboxSelected>>", lambda e: self.model.set(PROVIDERS[self.provider_keys[self.provider.current()]][1]))
        ttk.Label(ai, text="Model").grid(row=2, column=0, **pad)
        self.model = tk.StringVar(value=cfg["aiModel"] or PROVIDERS.get(cfg["aiProvider"], PROVIDERS["off"])[1])
        ttk.Entry(ai, textvariable=self.model, width=32).grid(row=2, column=1, **pad)
        ttk.Label(ai, text="API key").grid(row=3, column=0, **pad)
        self.had_key = ai_key() is not None
        self.key = tk.StringVar(value="••••••••" if self.had_key else "")
        ttk.Entry(ai, textvariable=self.key, width=32, show="•").grid(row=3, column=1, **pad)
        ttk.Label(ai, text="Base URL (Other only)").grid(row=4, column=0, **pad)
        self.base = tk.StringVar(value=cfg["aiBaseURL"])
        ttk.Entry(ai, textvariable=self.base, width=32).grid(row=4, column=1, **pad)
        ttk.Label(ai, text="Your key is saved only on this PC. Clear the field to remove it.",
                  foreground="#666").grid(row=5, column=0, columnspan=2, **pad)

        buttons = ttk.Frame(w, padding=(12, 0, 12, 12))
        buttons.pack(fill="x")
        ttk.Button(buttons, text="Show tutorial", command=lambda: (w.destroy(), app.start_tutorial())).pack(side="left")
        ttk.Button(buttons, text="Save", command=self.save).pack(side="right")
        ttk.Button(buttons, text="Cancel", command=w.destroy).pack(side="right", padx=6)
        self.w = w
        w.update_idletasks()
        w.geometry(f"+{(w.winfo_screenwidth() - w.winfo_width()) // 2}+{(w.winfo_screenheight() - w.winfo_height()) // 3}")
        w.focus_force()

    def save(self):
        minutes = parse_minutes
        choices = [m for m, v in self.choice_vars.items() if v.get()] or [5, 15, 30, 60]
        new = {
            "userName": self.name.get().strip() or "Bro",
            "character": self.char_folders[self.character.current()] if self.character.current() >= 0 else self.app.cfg["character"],
            "walking": self.walking.get(),
            "startWithWindows": self.startup.get(),
            "waterIntervalMinutes": int(self.water.get().split()[0]),
            "distractingSites": [n for n, v in self.site_vars.items() if v.get()],
            "askBudget": self.ask.get(),
            "budgetOptionsMinutes": choices,
            "defaultBudgetMinutes": minutes(self.default.get()),
            "closeAfterMinutes": minutes(self.close_after.get()),
            "aiProvider": self.provider_keys[self.provider.current()],
            "aiModel": self.model.get().strip(),
            "aiBaseURL": self.base.get().strip(),
        }
        key = self.key.get().strip()
        key_changed = key != ("••••••••" if self.had_key else "")
        self.w.destroy()
        self.app.apply_settings(new, key, key_changed)


def single_instance():
    """Only one Bro at a time."""
    ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\BroDesktopCompanion")
    return ctypes.windll.kernel32.GetLastError() != 183          # ERROR_ALREADY_EXISTS


if __name__ == "__main__":
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)            # crisp on 125% / 150% displays
    except Exception:
        pass
    if single_instance():
        try:
            Bro().run()
        except Exception:
            log(traceback.format_exc())
            raise
