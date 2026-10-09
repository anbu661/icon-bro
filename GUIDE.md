# Build "Bro": an AI desktop companion (macOS + Windows)

Bro is a 3D cartoon character who lives on your desktop. He:

- walks around
- reminds you to drink water
- nags you when you spend too long on YouTube or Instagram
- leaps up and smashes the tab when your time runs out
- talks with you by voice
- tidies folders when you ask

> **API keys:** never paste a key into code, chat or a shared file. Store it only in an environment variable or in the app's key file, which stays on your machine.

---

## 1. Tools

| Purpose | macOS | Windows |
|---|---|---|
| Character image | ChatGPT (image generation) or Gemini | same |
| Character animation (walk, drink, react) | Kling AI (image-to-video, Motion Control), Sora, Meta AI or Gemini Veo | same |
| Background removal | macOS Vision (built in), via `tools/cutout.swift` | `rembg` (Python), via `windows/import_character.py` |
| Video to frames, loop trimming | ffmpeg (`brew install ffmpeg`) | ffmpeg (`winget install Gyan.FFmpeg`) |
| App language | Swift 6 + AppKit (Xcode Command Line Tools) | Python 3.11+ with tkinter |
| Voice in (speech-to-text) | Sarvam AI `saaras:v3` (fallback: Apple Speech) | Sarvam AI `saaras:v3` |
| Voice out (text-to-speech) | Sarvam AI `bulbul:v3` (fallback: AVSpeechSynthesizer) | Sarvam AI `bulbul:v3` via `winsound` |
| Brain (chat + intent) | Sarvam `sarvam-105b-conversations` (fallback: Claude Code CLI `claude -p`, Haiku) | same |
| Browser watch / tab close | AppleScript (`osascript`) | Window title via Win32 API, then Ctrl+W |
| Folder tidy | Swift `FileManager`, with an undo log | Python `shutil`, with an undo log |
| Packaging | `build.sh` produces `Bro.app` | PyInstaller produces `Bro.exe` |

API key: create one at **dashboard.sarvam.ai** (free credits to start).

---

## 2. Create the character (both platforms)

### 2a. Base image (ChatGPT / Gemini)

> 3D Pixar-style animated character of **[person or actor]**, full body, standing facing the camera, friendly smile, hands in pockets, wearing **[outfit, e.g. blue denim jacket, grey t-shirt, black jeans, white sneakers]**. Plain solid white background, soft studio lighting, entire body visible including shoes.

Save it as `idle.png`.

### 2b. Walk cycle (Kling, image-to-video, 5 s)

Use `idle.png` as the start image, with this prompt:

> The character turns to the side and walks in place facing right, a natural relaxed walk cycle, arms swinging gently. Static camera, plain white background, full body always visible, no camera movement. 3 seconds, loopable.

Save it as `walk.mp4`.

### 2c. Water reminder (Kling, image-to-video, 5 s)

> The character reaches behind his back with his right hand, pulls out a clear plastic water bottle filled with water, smiles warmly and extends the bottle toward the camera at chest height, as if offering it to the viewer, then holds that pose steady with a friendly, encouraging expression and a small nod. Natural, smooth movement. Static camera, plain white background, full body visible from head to sneakers the whole time, no zoom, no camera movement.

Negative prompt:

> camera movement, zoom, cropped feet, cut off head, background objects, extra hands, extra fingers, distorted bottle, blurry, text, watermark

Save it as `water.mp4`. It plays once and holds the last frame until you press YES.

### 2d. Other moods (image or 3–5 s video, same start image)

| File | Prompt (start each one with "Same character, same outfit, plain white background, full body, static camera") |
|---|---|
| `happy` | laughs and gives a big thumbs up |
| `warn` | crosses his arms, raises one eyebrow, shakes his head slowly |
| `angry` | frowns and points firmly at the camera |

### 2e. Optional: copy motion from a reference video

Use **Kling Motion Control**:

1. Upload `idle.png` as the character.
2. Upload a reference clip of the movement you want.
3. Use this prompt: *"plain white background, static camera, full body visible"*.

Your character then performs that movement with his own face and outfit.

---

## 3. Cut out the background and import

Put all files in one folder, named by pose: `idle.png`, `walk.mp4`, `water.mp4`, `happy.mp4`, `warn.png`, `angry.png`.

**Find a seamless walk loop first** (both platforms):

```bash
python windows/import_character.py --find-loop walk.mp4
# prints e.g.: ffmpeg -ss 2.692 -i "walk.mp4" -frames:v 31 -an walk.mp4   <- run it to trim
```

**macOS:**

```bash
cd desktop-buddy
FPS=24 ./import-character.sh denim ~/Downloads/bro-poses
```

**Windows (PowerShell):**

```powershell
cd desktop-buddy\windows
python import_character.py denim C:\Users\<you>\Downloads\bro-poses
```

Poses end up in `stickers/<name>/` as either `<pose>.png` or a `<pose>/` folder of numbered frames.

---

## 4. Build the app

### macOS

1. Install the tools:
   ```bash
   xcode-select --install
   brew install ffmpeg
   ```
2. Get the project folder `desktop-buddy/`. These are its files:
   ```
   Sources/main.swift       window, character animation, walking/running, water reminder, browser watch, tab smash, menu
   Sources/Chat.swift       conversation logic, Claude CLI fallback, tidy actions, chat-follows-character
   Sources/ChatPanel.swift  denim-styled chat window (stitching, leather patch, bubbles, copper mic)
   Sources/Sarvam.swift     Sarvam chat / speech-to-text / text-to-speech, mic recorder with silence detection
   Sources/Voice.swift      Apple speech fallback (SFSpeechRecognizer, AVSpeechSynthesizer)
   Sources/Tidy.swift       sort files into Images/Videos/Audio/Documents/Archives + undo log
   tools/cutout.swift       background removal with macOS Vision
   import-character.sh      images/clips -> poses
   build.sh                 compiles Bro.app, writes Info.plist (permission texts), signs, installs
   ```
3. Build and run:
   ```bash
   cd desktop-buddy
   ./build.sh
   open ~/Applications/Bro.app
   ```
4. Add the Sarvam key: right-click Bro, choose **Set Sarvam API key…**, paste it and click **Save**. It's stored in `~/Library/Application Support/DesktopBuddy/sarvam.key` with permissions 600.
5. Allow the macOS prompts when they appear: **Automation** (browser), **Microphone**, **Speech Recognition** and **Downloads folder**.
6. Optional: right-click Bro and turn on **Start at login**.

### Windows 10/11

1. Install the tools:
   ```powershell
   winget install Python.Python.3.12
   winget install Gyan.FFmpeg
   ```
2. Install the Python packages:
   ```powershell
   cd desktop-buddy\windows
   python -m pip install -r requirements.txt
   ```
3. Store the API key (in a new terminal afterwards):
   ```powershell
   setx SARVAM_API_KEY "<your key>"
   ```
   Or save the key alone in `%APPDATA%\Bro\sarvam.key`.
4. Import the character (step 3), then run Bro:
   ```powershell
   python bro.py
   ```
5. Package it as an app:
   ```powershell
   pyinstaller --noconsole --onefile --name Bro bro.py
   ```
   The result is `dist\Bro.exe`.
6. Start at login: press Win+R, type `shell:startup`, and put a shortcut to `Bro.exe` there.
7. Allow the microphone: go to Settings → Privacy & security → Microphone and turn on **Let desktop apps access your microphone**.

The Windows script is `windows/bro.py`, a single file:

- **Character window:** a transparent tkinter window using the `-transparentcolor` key.
- **Distraction detection:** foreground window title plus process name, via Win32 `ctypes`.
- **Tab close:** `keybd_event` sends Ctrl+W.
- **Recording:** `sounddevice` with RMS silence detection.
- **Playback:** `winsound.PlaySound(SND_MEMORY)`.
- **Background work:** every network call runs on a thread and hands back to the UI through a queue.

---

## 5. Settings (`config.json`)

**Location:**

- macOS: `~/Library/Application Support/DesktopBuddy/config.json`
- Windows: `%APPDATA%\Bro\config.json`

Restart Bro after editing.

```json
{
  "userName": "YourName",
  "character": "denim",
  "waterIntervalMinutes": 45,
  "distractingSites": ["youtube.com", "instagram.com"],
  "nagAfterMinutes": 15,
  "closeAfterMinutes": 25,
  "warningSeconds": 60,
  "nagRepeatSeconds": 120,
  "breakResetMinutes": 10,
  "closeMode": "tabs",
  "fps": 24,
  "walkFacesRight": true,
  "walking": true,
  "useSarvam": true,
  "sarvamSpeaker": "varun",
  "sarvamChatModel": "sarvam-105b-conversations",
  "chatModel": "haiku"
}
```

| Setting | 30-second demo | Normal |
|---|---|---|
| `nagAfterMinutes` | 0.17 | 15 |
| `closeAfterMinutes` | 0.5 | 25 |
| `warningSeconds` | 10 | 60 |
| `nagRepeatSeconds` | 5 | 120 |
| `breakResetMinutes` | 0.5 | 10 |

Platform differences:

- **Windows `distractingSites`:** match the window title (`"YouTube"`, `"Instagram"`), because Windows can't read the URL.
- **macOS `closeMode`:** `"quit"` quits the whole browser instead of closing tabs.

**Sarvam male voices:** shubh, aditya, rahul, rohan, amit, dev, varun, kabir, aayan, advait, anand, tarun, sunny, mani, gokul, mohit, rehan, soham, manan, ratan.

---

## 6. Brain system prompt (used by both versions)

```
You are Bro, <name>'s cheeky but caring 3D cartoon companion who lives on his screen.
You remind him to drink water and kick him off YouTube/Instagram when he doomscrolls.
Talk like his close friend: simple, warm English. Call him "bro" naturally.
Never use "da", "machan", "macha", "dei" or "mate".
Your replies are spoken aloud: keep them to 1-2 short, playful sentences. No markdown, no emoji.
Reply in the language he uses: English, Tamil (in Tamil script), or Tanglish.
You can also act on his computer. Respond ONLY with JSON:
{"reply": string, "action": null | {"type":"tidy","folder":string} | {"type":"undo_tidy"}
 | {"type":"drank_water"} | {"type":"walk","direction":"left"|"right"}}
- tidy: he wants a folder cleaned/organised/sorted. Say you'll take a look; the app counts files and asks to confirm.
- undo_tidy: put the last tidy back. - drank_water: he drank water. - walk: move left/right.
Facts: <n> glasses of water today; <m> min on distracting sites right now.
```

The app, not the AI, does every file move. It does so only after you say "yes", and it logs each move so "undo" can restore them.

---

## 7. API endpoints (Sarvam)

| Use | Call |
|---|---|
| Chat | `POST https://api.sarvam.ai/v1/chat/completions`. Headers: `api-subscription-key`, `Authorization: Bearer`. Body: `model`, `messages` |
| Speech to text | `POST https://api.sarvam.ai/speech-to-text`. Multipart: `file` (16 kHz mono WAV), `model=saaras:v3`, `mode=codemix`, `language_code=unknown` |
| Text to speech | `POST https://api.sarvam.ai/text-to-speech`. JSON: `text`, `language_code` (en-IN / ta-IN …), `speaker`, `model=bulbul:v3`, `output_audio_codec=wav`. Response: `audios[0]` (base64) |

---

## 8. Test checklist

1. Bro appears, walks, and turns to face the way he's walking.
2. Right-click → **Remind me to drink now**. The pop-up shows **YES** and **Remind me later**. YES makes him jump, say "Nice!" and run across the screen.
3. Switch to the 30-second demo settings and open YouTube:
   - nags at 10 s
   - countdown at 20 s
   - leap, 💥, tab closed and hop back at 30 s
4. Double-click Bro (a single click makes him do his swag move), then say *"tidy my downloads folder"*. He reports the counts and asks. Say *"yes"*: files are sorted and the folder opens. Say *"undo"*: everything goes back.
5. Ask something in Tamil. He replies in Tamil, in the chosen voice.
6. Open the chat. Bro stays next to it, doesn't wander, and both move when you drag either one.
7. Before a demo, click 🗑 in the chat header (or right-click Bro → **Clear chat**). The messages, conversation memory and any pending tidy are wiped, and a fresh greeting appears.

---

## 9. Troubleshooting

| Problem | Fix |
|---|---|
| macOS: Bro doesn't react to YouTube | System Settings → Privacy & Security → Automation → Bro: turn on your browser. Permissions reset after each rebuild, because the app is ad-hoc signed. |
| macOS: can't paste into a text box | The app needs an Edit menu (already in `installEditMenu()`). |
| Character shrinks while walking | Make the character view wide enough that every pose scales by height. |
| Character freezes after the tab smash | Run the tab-closing script on a background thread or process, never the UI thread. |
| Walk loop "jumps" | Run `--find-loop` and trim `walk.mp4` to the reported frames. |
| Windows: jagged edges around the character | Expected with colour-key transparency. Use a higher-resolution source and keep `height` at 200–260. |
| No voice reply | Check the Sarvam key and credits. Bro falls back to the system voice (macOS) or text only (Windows). |
