# Bro 😎

A cartoon desktop buddy for **macOS** who lives on your screen, walks around, reminds you to drink water, keeps you
off YouTube, Instagram and OTT sites when you've had enough, tidies your folders and chats with you. **Biscuit the
cat** is the default buddy; switch any time with right-click → **Character** (Bro (Denim), Iron Man, Drop or Buddy).

- **Water reminders.** Every 45 minutes he pops up with a water pose and asks *"Did you drink water?"*.
  **YES** logs a glass; he cheers and does a happy run across the screen. **Remind me later** makes him sad and he
  comes back in 10 minutes.
- **Screen-time guard.** Open YouTube, Instagram, Netflix, Prime Video, JioHotstar and more, and he asks
  *"How much time do you need?"* (5 min / 15 min / 30 min / 1 hr; 15 min if you don't answer). The question
  vanishes as soon as you pick, and he disappears with a poof into the menu bar, where 😎 counts down. Near the end
  he comes back to nag you, gets angry, then leaps up to the tab strip, smashes it and closes the tab.
- **Folder tidy.** Right-click → **Tidy a folder** (Downloads, Desktop or any folder). Images, videos, audio,
  documents and archives go into their own folders. He counts first and asks before moving anything; nothing is
  deleted, and **Undo last tidy** puts everything back. Works fully offline: no AI, no internet.
- **Chat.** Double-click him to chat. Offline he understands simple commands: *"tidy my downloads"*, *"undo"*,
  *"I drank water"*, *"walk left"*. Turn on **Agentic chat** in Settings with your own API key (OpenAI,
  Anthropic Claude, Google Gemini or any OpenAI-compatible service) for real conversations; he can still tidy and
  log water from chat.
- **Fun bits.** Single-click for his swag move, drag him anywhere, and he waves hello when he starts.
  **Minimise Bro** sends him off with a poof; bring him back from 😎 in the menu bar or from the Dock.
- **First-run tutorial.** A quick guided tour on first launch (Next → Next → Got it); replay it from right-click →
  **Show tutorial**.

> **Personal use only.** Iron Man is a Marvel character and his pose is a likeness of that character. Bro (Denim),
> Biscuit and the other buddies were made with AI image and video tools, just for fun. Don't publish or redistribute
> builds that contain them. This repository and its releases are private: friends and family need to be invited
> (repo **Settings → Collaborators**) and signed in to GitHub to download.

## Install

| Your computer | File |
|---|---|
| Mac with Apple Silicon (M1/M2/M3/M4…) or Intel, macOS 13 Ventura or newer | `Bro-1.0.dmg` |
| Windows 10/11 | Coming soon |

1. Download `Bro-1.0.dmg` from [Releases](../../releases/latest), open it and drag **Bro** into **Applications**.
2. Open Bro from Applications.

The app is **not code-signed with a paid Apple certificate**, so the first launch shows a warning. If macOS says it
*"could not verify"* Bro, click **Done**, then go to **System Settings → Privacy & Security**, scroll to
*"Bro was blocked…"* and click **Open Anyway**. After that it opens normally.

The first time you open YouTube or a streaming site, macOS asks *"Bro wants to control Google Chrome / Safari"*.
Click **OK**, or he can't see your tabs. Works with Google Chrome, Safari, Brave and Arc.

## How to use him

| Do this | What happens |
|---|---|
| **Click** | Swag move (or logs a glass when he's asking about water) |
| **Double-click** | Opens chat |
| **Drag** | Move him anywhere |
| **Right-click** | Everything else: Character, Tidy a folder, I drank water, Minimise, Settings, Show tutorial, Quit |
| **😎 in the menu bar** | Show / hide Bro, chat, settings, quit. Shows the time left while you're on a watched site |

## Settings

Right-click Bro → **Settings…**. Changes apply straight away:

- **You:** what Bro calls you (default *Bro*), character, walk around, start at login
- **Sites & OTT:** YouTube, Instagram, Facebook, X / Twitter, Reddit, Netflix, Prime Video, JioHotstar, JioCinema,
  SonyLIV, ZEE5, Disney+, aha, Sun NXT
- **Screen time:** ask how much time you need, the time choices, the default if you don't answer, water reminder interval
- **Agentic chat:** provider, model and your own API key

Everything is stored in `~/Library/Application Support/Bro/`: `config.json` for settings, `stickers/` for the
characters and `ai.key` for your API key (readable only by you). Bro ships with **no API keys**.

## Characters

Each character is a folder in `~/Library/Application Support/Bro/stickers/<name>/`. A pose is a single image
(`idle.png`) or a folder of frames (`walk/001.png`, `002.png`…) played in order:

| Pose | Used for |
|---|---|
| `idle` | Standing around (required) |
| `walk` / `run` | Walking around / the happy run after drinking water and the leap to the tab |
| `water` | Water reminder |
| `happy` | After *YES* |
| `warn` | Sad face after *Remind me later*, and nags |
| `angry` | Final warning and the tab smash |
| `hello2` | Swag move on single click |

`character.json` sets the display name, playback speed and which way the walk/run clips face. Missing poses fall
back to `idle`. Prompts used to make the characters (ChatGPT image + Kling image-to-video) are in
[characters/PROMPTS.md](characters/PROMPTS.md).

## Development

Swift + AppKit, no dependencies. Requires the Xcode command line tools.

```bash
./build.sh                       # personal build → ~/Applications/Bro.app
./build-share.sh                 # shareable build → dist/Bro-<version>.dmg (universal, no voice, no keys)
CHARS="biscuit denim" ./build-share.sh    # choose which characters to bundle (first = default + app icon)
FPS=24 ./import-character.sh biscuit ~/Downloads/biscuit-poses   # turn images/clips into a character
```

`import-character.sh` removes backgrounds on-device with Apple Vision and turns `.mp4` clips into frame folders.

## Project layout

```
Sources/main.swift      app, character animation, water reminders, screen-time guard, menus
Sources/Chat.swift      chat routing, offline commands
Sources/AIChat.swift    agentic chat (OpenAI / Anthropic / Gemini / OpenAI-compatible)
Sources/Settings.swift  Settings window and first-run tutorial
Sources/Tidy.swift      folder tidy + undo
Sources/Effects.swift   poof / sparkle effects
Sources/Edition.swift   personal vs share build, offline brain
tools/                  background cutout, sticker packing, app icon
characters/PROMPTS.md   prompts for making new characters
windows/                Windows version (in progress)
share/                  READ ME FIRST that goes inside the DMG
```

Made by Shaid · [shaid360.com](https://shaid360.com)
