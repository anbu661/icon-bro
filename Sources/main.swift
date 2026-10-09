import AppKit
import ServiceManagement

// MARK: - Config

struct Config: Codable {
    var waterIntervalMinutes: Double = 45
    var distractingSites: [String] = ["youtube.com", "instagram.com", "netflix.com", "primevideo.com", "hotstar.com",
                                      "jiocinema.com", "sonyliv.com", "zee5.com", "disneyplus.com", "aha.video", "sunnxt.com"]
    var askBudget: Bool = true              // ask "how much time do you need?" when a distracting site opens
    var budgetOptionsMinutes: [Double] = isShareBuild ? [5, 15, 30, 60] : [0.5, 5, 15, 30, 60]   // first = default if no answer
    var nagAfterMinutes: Double = 15        // first nag after this much continuous scrolling
    var closeAfterMinutes: Double = 25      // tabs get closed at this point
    var breakResetMinutes: Double = 10      // time away from the sites that resets the counter
    var warningSeconds: Double = 60         // final "closing it in N seconds" countdown before closing
    var nagRepeatSeconds: Double = 120      // gap between nags
    var voiceFirst: Bool = voiceEnabled             // clicking Buddy opens chat and starts listening
    var voiceReplies: Bool = voiceEnabled           // Buddy speaks his replies
    var chatModel: String = "haiku"         // Claude model used for chat (when Sarvam is off)
    var useSarvam: Bool = !isShareBuild              // use Sarvam AI for chat + voice when a key is set
    var sarvamSpeaker: String = "varun"     // Bulbul v3 voice: shubh, aditya, rahul, rohan, amit, dev, varun, kabir, vijay, mani, gokul…
    var sarvamChatModel: String = "sarvam-105b-conversations"
    var closeMode: String = "tabs"          // "tabs" = close only distracting tabs, "quit" = quit the browser
    var character: String = isShareBuild ? "biscuit" : "buddy"         // folder name inside stickers/
    var walking: Bool = true                // stroll left and right along the screen when idle
    var userName: String = isShareBuild ? "Bro" : macFirstName          // used in "Hey, <name>!"
    var fps: Double = isShareBuild ? 24 : 12                    // playback speed for animated (folder) poses
    var walkFacesRight: Bool = true         // which way the character faces in its walk frames
    var defaultBudgetMinutes: Double? = isShareBuild ? 15 : nil   // used when he doesn't answer "how much time?"
    var aiProvider: String = "off"          // agentic chat: off, openai, anthropic, gemini, custom
    var aiModel: String = ""                // empty = provider default
    var aiBaseURL: String = ""              // for "custom" (any OpenAI-compatible service)
    var tutorialDone: Bool = !isShareBuild  // first-run walkthrough shown?
    var runFacesRight: Bool = !isShareBuild          // same, for the run/ clip

    init() {}
    // Tolerant decoding so adding a new setting never wipes the user's existing config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        waterIntervalMinutes = try c.decodeIfPresent(Double.self, forKey: .waterIntervalMinutes) ?? d.waterIntervalMinutes
        distractingSites = try c.decodeIfPresent([String].self, forKey: .distractingSites) ?? d.distractingSites
        nagAfterMinutes = try c.decodeIfPresent(Double.self, forKey: .nagAfterMinutes) ?? d.nagAfterMinutes
        closeAfterMinutes = try c.decodeIfPresent(Double.self, forKey: .closeAfterMinutes) ?? d.closeAfterMinutes
        breakResetMinutes = try c.decodeIfPresent(Double.self, forKey: .breakResetMinutes) ?? d.breakResetMinutes
        warningSeconds = try c.decodeIfPresent(Double.self, forKey: .warningSeconds) ?? d.warningSeconds
        nagRepeatSeconds = try c.decodeIfPresent(Double.self, forKey: .nagRepeatSeconds) ?? d.nagRepeatSeconds
        voiceFirst = try c.decodeIfPresent(Bool.self, forKey: .voiceFirst) ?? d.voiceFirst
        voiceReplies = try c.decodeIfPresent(Bool.self, forKey: .voiceReplies) ?? d.voiceReplies
        chatModel = try c.decodeIfPresent(String.self, forKey: .chatModel) ?? d.chatModel
        useSarvam = try c.decodeIfPresent(Bool.self, forKey: .useSarvam) ?? d.useSarvam
        sarvamSpeaker = try c.decodeIfPresent(String.self, forKey: .sarvamSpeaker) ?? d.sarvamSpeaker
        sarvamChatModel = try c.decodeIfPresent(String.self, forKey: .sarvamChatModel) ?? d.sarvamChatModel
        askBudget = try c.decodeIfPresent(Bool.self, forKey: .askBudget) ?? d.askBudget
        budgetOptionsMinutes = try c.decodeIfPresent([Double].self, forKey: .budgetOptionsMinutes) ?? d.budgetOptionsMinutes
        closeMode = try c.decodeIfPresent(String.self, forKey: .closeMode) ?? d.closeMode
        character = try c.decodeIfPresent(String.self, forKey: .character) ?? d.character
        walking = try c.decodeIfPresent(Bool.self, forKey: .walking) ?? d.walking
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? d.userName
        fps = try c.decodeIfPresent(Double.self, forKey: .fps) ?? d.fps
        walkFacesRight = try c.decodeIfPresent(Bool.self, forKey: .walkFacesRight) ?? d.walkFacesRight
        runFacesRight = try c.decodeIfPresent(Bool.self, forKey: .runFacesRight) ?? d.runFacesRight
        defaultBudgetMinutes = try c.decodeIfPresent(Double.self, forKey: .defaultBudgetMinutes) ?? d.defaultBudgetMinutes
        aiProvider = try c.decodeIfPresent(String.self, forKey: .aiProvider) ?? d.aiProvider
        aiModel = try c.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        aiBaseURL = try c.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? d.aiBaseURL
        tutorialDone = try c.decodeIfPresent(Bool.self, forKey: .tutorialDone) ?? d.tutorialDone
    }
}

let supportDir: URL = {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/\(appSupportName)")
    try? FileManager.default.createDirectory(at: url.appendingPathComponent("stickers"), withIntermediateDirectories: true)
    return url
}()
let configURL = supportDir.appendingPathComponent("config.json")

func loadConfig() -> Config {
    if let data = try? Data(contentsOf: configURL), let cfg = try? JSONDecoder().decode(Config.self, from: data) {
        return cfg
    }
    let cfg = Config()
    saveConfig(cfg)
    return cfg
}

func saveConfig(_ cfg: Config) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? enc.encode(cfg).write(to: configURL)
}

// MARK: - Lines

enum Mood: String { case idle, happy, water, warn, angry }

let waterLines = [
    "Hey, %@!\nDid you drink water?",
    "Hey, %@!\nWater break time 💧",
    "%@, your brain is 75%% water.\nTop it up!",
]
let thanksLines = ["Nice! 🎉", "That's my guy! 💪", "Hydrated king 👑", "Nice! Keep it up."]
let nagLines = [
    "You've been on %1$@ for %2$@. Wrap it up?",
    "%2$@ of %1$@... the reels will still be there tomorrow.",
    "Still on %1$@? %2$@ now. I'm watching you. 👀",
]
let angryLines = [
    "%2$@ on %1$@! Last warning: closing it in %3$ld seconds. 😤",
    "That's it. %1$@ gets closed in %3$ld seconds. %2$@ is enough!",
]

// MARK: - Browser access (AppleScript)

struct Browser { let bundleID: String; let name: String; let isSafari: Bool }

let browsers = [
    Browser(bundleID: "com.google.Chrome", name: "Google Chrome", isSafari: false),
    Browser(bundleID: "com.brave.Browser", name: "Brave Browser", isSafari: false),
    Browser(bundleID: "company.thebrowser.Browser", name: "Arc", isSafari: false),
    Browser(bundleID: "com.apple.Safari", name: "Safari", isSafari: true),
]

@discardableResult
func runAppleScript(_ source: String) -> (String?, Int?) {
    var err: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
    if let err { return (nil, err[NSAppleScript.errorNumber] as? Int) }
    return (result?.stringValue, nil)
}

func activeURL(of b: Browser) -> (String?, Int?) {
    let tab = b.isSafari ? "current tab" : "active tab"
    return runAppleScript("tell application \"\(b.name)\" to if (count of windows) > 0 then get URL of \(tab) of front window")
}

/// Rough on-screen centre of the browser's active tab (Cocoa coordinates). Browsers don't expose tab
/// geometry over AppleScript, so this is estimated from the window bounds and the tab's index.
func activeTabPoint(of b: Browser) -> NSPoint? {
    let script: String
    if b.isSafari {
        script = "tell application \"Safari\" to {bounds of front window, index of current tab of front window, count of tabs of front window}"
    } else if b.name == "Arc" {
        script = "tell application \"Arc\" to {bounds of front window, 1, 1}"
    } else {
        script = "tell application \"\(b.name)\" to {bounds of front window, active tab index of front window, count of tabs of front window}"
    }
    var err: NSDictionary?
    guard let d = NSAppleScript(source: script)?.executeAndReturnError(&err), err == nil, d.numberOfItems == 3,
          let bounds = d.atIndex(1), bounds.numberOfItems == 4,
          let left = bounds.atIndex(1)?.int32Value, let top = bounds.atIndex(2)?.int32Value,
          let right = bounds.atIndex(3)?.int32Value,
          let index = d.atIndex(2)?.int32Value, let count = d.atIndex(3)?.int32Value else { return nil }
    let l = CGFloat(left), t = CGFloat(top), r = CGFloat(right)
    let i = CGFloat(index), n = CGFloat(max(1, count))
    var x: CGFloat, y: CGFloat
    if b.isSafari {                       // tab bar under the toolbar, tabs share the full width
        let w = (r - l) / n
        x = l + w * (i - 0.5); y = t + 64
    } else if b.name == "Arc" {           // tabs live in the left sidebar
        x = l + 130; y = t + 110
    } else {                              // Chromium: tab strip in the title bar, after the traffic lights
        let w = min(240, (r - l - 180) / n)
        x = l + 80 + w * (i - 0.5); y = t + 20
    }
    // AppleScript bounds are top-left based on the primary screen; Cocoa is bottom-left based.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSPoint(x: x, y: primaryHeight - y)
}

/// Closes the distracting tabs in the background (one script per browser) so Bro's animation never freezes
/// while the browser works through its windows.
func closeDistracting(in b: Browser, sites: [String], mode: String) {
    let script: String
    if mode == "quit" {
        script = "tell application \"\(b.name)\" to quit"
    } else {
        let closes = sites.map { "close (every tab of w whose URL contains \"\($0)\")" }.joined(separator: "\n")
        script = """
        tell application "\(b.name)"
            repeat with w in windows
                \(closes)
            end repeat
        end tell
        """
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()        // fire and forget
}

// MARK: - Speech bubble

final class PillButton: NSButton {
    var handler: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.handler = handler
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 13
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.black])
        target = self
        action = #selector(fire)
        sizeToFit()
        frame.size = NSSize(width: frame.width + 26, height: 26)
    }
    @objc func fire() { handler?() }
}

final class BubbleView: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    private var buttons: [PillButton] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Lays out the text (and buttons) and returns the height needed.
    func show(_ text: String, buttons specs: [(String, () -> Void)], width: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let font = NSFont(descriptor: NSFont.systemFont(ofSize: 17, weight: .black).fontDescriptor
                            .withDesign(.rounded) ?? NSFont.systemFont(ofSize: 17).fontDescriptor, size: 17)
            ?? .systemFont(ofSize: 17, weight: .black)
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 1, green: 0.86, blue: 0.1, alpha: 1),
            .strokeColor: NSColor(calibratedRed: 0.75, green: 0.08, blue: 0.08, alpha: 1),
            .strokeWidth: -4,
            .paragraphStyle: para,
        ])
        buttons.forEach { $0.removeFromSuperview() }
        buttons = specs.map { PillButton($0.0, handler: $0.1) }

        let textH = label.sizeThatFits(NSSize(width: width, height: 300)).height
        // pack buttons into centred rows that fit the width
        var rows: [[PillButton]] = []
        for b in buttons {
            let used = (rows.last ?? []).reduce(0) { $0 + $1.frame.width + 8 }
            if rows.isEmpty || used + b.frame.width > width { rows.append([b]) } else { rows[rows.count - 1].append(b) }
        }
        let rowH: CGFloat = 32
        let buttonsH = CGFloat(rows.count) * rowH
        label.frame = NSRect(x: 0, y: buttonsH, width: width, height: textH)
        for (r, row) in rows.enumerated() {
            let total = row.reduce(0) { $0 + $1.frame.width } + CGFloat(row.count - 1) * 8
            var x = (width - total) / 2
            for b in row {
                b.frame.origin = NSPoint(x: x, y: buttonsH - CGFloat(r + 1) * rowH + 3)
                x += b.frame.width + 8
                addSubview(b)
            }
        }
        return textH + buttonsH
    }
}

// MARK: - Character view (click / drag / right-click)

final class BuddyView: NSImageView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onGrab: (() -> Void)?
    private var pendingClick: DispatchWorkItem?
    var onMenu: ((NSEvent) -> Void)?
    private var dragStart: NSPoint?
    private var moved = false

    override func mouseDown(with event: NSEvent) { dragStart = event.locationInWindow; moved = false; onGrab?() }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let win = window else { return }
        let p = event.locationInWindow
        if abs(p.x - start.x) + abs(p.y - start.y) > 3 { moved = true }
        win.setFrameOrigin(NSPoint(x: win.frame.origin.x + p.x - start.x, y: win.frame.origin.y + p.y - start.y))
    }
    override func mouseUp(with event: NSEvent) {
        if moved {
            UserDefaults.standard.set(NSStringFromPoint(window!.frame.origin), forKey: "origin")
        } else if event.clickCount >= 2 {
            pendingClick?.cancel()          // it was a double click, not a single one
            pendingClick = nil
            onDoubleClick?()
        } else {
            // wait to see whether a second click is coming
            let work = DispatchWorkItem { [weak self] in self?.onClick?() }
            pendingClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
        }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var config = loadConfig()
    var panel: NSPanel!
    let buddy = BuddyView()
    let bubble = BubbleView(frame: NSRect(x: 10, y: 200, width: 240, height: 74))
    var bubbleTimer: Timer?
    var waitingForWater = false

    // chat
    var chatPanel: ChatPanel?
    let macEars = Listener()
    let sarvamEars = SarvamListener()
    let macMouth = Speaker()
    lazy var sarvamMouth = SarvamSpeaker(fallback: macMouth, voice: { [weak self] in self?.config.sarvamSpeaker ?? "shubh" })
    var useSarvam: Bool { config.useSarvam && Sarvam.apiKey != nil }
    var listener: Ears { useSarvam ? sarvamEars : macEars }
    var speaker: Mouth { useSarvam ? sarvamMouth : macMouth }
    var chatOffset = NSPoint.zero
    var waterTimer: Timer?
    var settingsWindow: SettingsWindow?
    var tutorialStep = 0
    var sessionBudget: Double?              // seconds he chose for this YouTube/OTT session
    var askingBudget = false
    var askToken: UUID?
    var statusItem: NSStatusItem?
    var isMinimized = false
    var swagToken: UUID?
    var syncingChat = false
    var chatHistory: [String] = []
    var pendingTidy: TidyPlan?

    // distraction tracking
    var distractedSeconds: Double = 0
    var lastDistracted = Date.distantPast
    var lastNag: Double = 0
    var finalWarningAt: Date?
    var permissionWarned = false
    let pollInterval: Double = 2

    var waterCountToday: Int {
        get {
            let key = "water-\(Self.today)"
            return UserDefaults.standard.integer(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: "water-\(Self.today)") }
    }
    static var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        installBundledStickers()
        installEditMenu()
        installStatusItem()

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 350),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        buddy.frame = NSRect(x: 10, y: 0, width: 240, height: 195)
        buddy.imageScaling = .scaleProportionallyUpOrDown
        buddy.wantsLayer = true
        buddy.onClick = { [weak self] in self?.clicked() }
        buddy.onDoubleClick = { [weak self] in self?.toggleChat() }
        buddy.onMenu = { [weak self] e in self?.showMenu(e) }
        buddy.onGrab = { [weak self] in self?.stopWalking() }
        bubble.isHidden = true
        content.addSubview(bubble)
        content.addSubview(buddy)
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        if let layer = buddy.layer {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0)
            layer.position = CGPoint(x: buddy.frame.midX, y: buddy.frame.minY)
        }

        if let saved = UserDefaults.standard.string(forKey: "origin") {
            panel.setFrameOrigin(NSPointFromString(saved))
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 280, y: screen.minY + 20))
        }
        panel.orderFrontRegardless()

        if frames(named: "walk").isEmpty { startBobbing() }
        sayHello()
        if !config.tutorialDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in self?.startTutorial() }
        }
        restartWaterTimer()
        Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            self?.maybeWander()
        }
        // `open Buddy.app --args --practice-smash`: rehearse the tab attack without closing anything
        // `--test-mood=warn` etc.: show a pose without waiting for its trigger
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--test-mood=") }),
           let mood = Mood(rawValue: String(arg.dropFirst("--test-mood=".count))) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.setMood(mood)
                self.say("You've been on Youtube for 15 min. Wrap it up, bro?", for: 10)
            }
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.openSettings() }
        }
        if CommandLine.arguments.contains("--test-ask") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.askForBudget("YouTube") }
        }
        if CommandLine.arguments.contains("--test-minimize") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.minimizeBro() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { self.showBro() }
        }
        if CommandLine.arguments.contains("--test-water") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.waterReminder() }
        }
        if CommandLine.arguments.contains("--test-water-yes") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.waterReminder() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.drankWater() }
        }
        if CommandLine.arguments.contains("--open-chat") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.openChat(listen: false)
                self.chatPanel?.add(self.config.userName, "tidy my downloads folder da")
                self.chatPanel?.add("Bro", "In Downloads I found 113 images, 42 videos and 62 documents. Shall I sort them into folders, bro?")
                self.chatPanel?.showTyping()
            }
        }
        if CommandLine.arguments.contains("--practice-smash") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.practiceSmash() }
        }
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkBrowsers()
        }
    }

    /// Background apps have no menu bar, so ⌘C / ⌘V / ⌘A do nothing in text fields without this.
    func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Bro")
        appMenu.addItem(withTitle: "Show Bro", action: #selector(showBro), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "Quit Bro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: stickers

    var stickersDir: URL { supportDir.appendingPathComponent("stickers") }

    /// Copies the stickers shipped in the app bundle into Application Support so users can add their own next to them.
    func installBundledStickers() {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("stickers"),
              let chars = try? FileManager.default.contentsOfDirectory(atPath: bundled.path) else { return }
        for c in chars where !FileManager.default.fileExists(atPath: stickersDir.appendingPathComponent(c).path) {
            try? FileManager.default.copyItem(at: bundled.appendingPathComponent(c), to: stickersDir.appendingPathComponent(c))
        }
    }

    var characters: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: stickersDir.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    // Per-character settings live in stickers/<name>/character.json; config values are the fallback.
    struct CharacterInfo: Codable {
        var name: String?
        var walkFacesRight: Bool?
        var runFacesRight: Bool?
        var fps: Double?
    }

    func characterInfo(_ folder: String) -> CharacterInfo? {
        let url = stickersDir.appendingPathComponent(folder).appendingPathComponent("character.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CharacterInfo.self, from: $0) }
    }

    func displayName(_ folder: String) -> String { characterInfo(folder)?.name ?? folder.capitalized }
    var charFPS: Double { characterInfo(config.character)?.fps ?? config.fps }
    var charWalkFacesRight: Bool { characterInfo(config.character)?.walkFacesRight ?? config.walkFacesRight }
    var charRunFacesRight: Bool { characterInfo(config.character)?.runFacesRight ?? config.runFacesRight }

    /// Switches character everywhere: on screen, chat avatar, Dock icon.
    func switchCharacter(_ folder: String) {
        config.character = folder
        saveConfig(config)
        chatPanel?.setAvatar(image(for: .idle))
        if isMinimized, let face = image(for: .idle).flatMap(faceCrop) { NSApp.applicationIconImage = face }
        sayHello()
    }

    static let imageExts = ["png", "heic", "jpg", "jpeg", "webp", "gif", "svg"]

    /// A pose is either `<name>.png` (one still) or a `<name>/` folder of frames played in name order.
    func frames(named name: String) -> [NSImage] {
        let base = stickersDir.appendingPathComponent(config.character).appendingPathComponent(name)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue {
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
                .filter { Self.imageExts.contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
            return files.compactMap { NSImage(contentsOf: base.appendingPathComponent($0)) }
        }
        for ext in Self.imageExts {
            if let img = NSImage(contentsOf: base.appendingPathExtension(ext)) { return [img] }
        }
        return []
    }

    func frames(for mood: Mood) -> [NSImage] {
        let f = frames(named: mood.rawValue)
        return f.isEmpty ? frames(named: Mood.idle.rawValue) : f
    }

    func image(for mood: Mood) -> NSImage? { frames(for: mood).first }

    var poseTimer: Timer?

    /// Loops by default; with `loop: false` plays once and holds the last frame (e.g. holding out the bottle).
    func play(_ frames: [NSImage], every interval: Double, loop: Bool = true) {
        poseTimer?.invalidate()
        poseTimer = nil
        buddy.image = frames.first ?? NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)
        guard frames.count > 1 else { return }
        var i = 0
        poseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            i += 1
            if i >= frames.count {
                if !loop { t.invalidate(); return }
                i = 0
            }
            self?.buddy.image = frames[i]
        }
    }

    func setMood(_ mood: Mood) {
        stopWalking()
        play(frames(for: mood), every: 1 / charFPS, loop: mood == .idle)
        if mood == .angry { shake() }
        if mood == .happy { jump() }
    }

    /// Single-click trick: the hello2 swag move, once, then back to standing.
    func swag() {
        guard !isAttacking else { return }
        let clip = frames(named: "hello2")
        guard !clip.isEmpty else { setMood(.happy); return }
        stopWalking()
        play(clip, every: 1 / charFPS, loop: false)
        let token = UUID()
        swagToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(clip.count) / charFPS + 0.2) { [weak self] in
            guard let self, self.swagToken == token, !self.isWalking, !self.isAttacking, !self.waitingForWater else { return }
            self.setMood(.idle)
        }
    }

    /// Startup greeting: hello1 (wave) then hello2 (swag), played once, then back to idle.
    func sayHello() {
        let clip = frames(named: "hello1") + frames(named: "hello2") + frames(named: "hello")
        let seconds = max(4, Double(clip.count) / charFPS + 0.3)
        say("Hey, \(config.userName)! 👋", for: seconds)
        if clip.isEmpty { setMood(.idle); return }
        play(clip, every: 1 / charFPS, loop: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.isWalking, !self.isAttacking, !self.waitingForWater else { return }
            self.setMood(.idle)
        }
    }

    // MARK: walking

    var walkTimer: Timer?
    var walkTargetX: CGFloat = 0
    let walkSpeed: CGFloat = 70     // points per second
    let runSpeed: CGFloat = 300     // with a real run/ clip
    var currentSpeed: CGFloat = 70

    var isWalking: Bool { walkTimer != nil }

    func mirrored(_ img: NSImage) -> NSImage {
        NSImage(size: img.size, flipped: false) { r in
            let t = NSAffineTransform()
            t.translateX(by: r.width, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
            img.draw(in: r)
            return true
        }
    }

    /// Every so often, if nothing else is going on, take a stroll.
    func maybeWander() {
        guard config.walking, !isWalking, !isAttacking, !isMinimized, chatPanel?.isVisible != true, bubble.isHidden, !waitingForWater, finalWarningAt == nil,
              Bool.random() else { return }
        walk()
    }

    /// A fast dash: same walk cycle, legs and feet sped up to match.
    /// A real run/ clip if the character has one; otherwise a brisk jog on the walk cycle
    /// (speeding a walk up a lot just looks like fast-forward).
    func run(to x: CGFloat? = nil) {
        if !frames(named: "run").isEmpty {
            walk(to: x, speed: runSpeed, cycleName: "run", legPace: 1)
        } else {
            walk(to: x, speed: 125, legPace: 1.7)
            bounce(period: 0.3, height: 5)
        }
    }

    func bounce(period: Double, height: CGFloat) {
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, height, 0]
        hop.duration = period
        hop.repeatCount = .infinity
        hop.isAdditive = true
        hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        buddy.layer?.add(hop, forKey: "step")
    }

    /// `legPace` = how fast the cycle plays relative to normal; ground speed and leg speed should roughly match.
    func walk(to x: CGFloat? = nil, speed: CGFloat? = nil, cycleName: String = "walk", legPace: Double? = nil) {
        guard let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let minX = screen.minX - 40, maxX = screen.maxX - panel.frame.width + 40
        let current = panel.frame.origin.x
        var target = x ?? CGFloat.random(in: minX...maxX)
        if x == nil && abs(target - current) < 150 {
            target = current < (minX + maxX) / 2 ? min(maxX, current + 250) : max(minX, current - 250)
        }
        stopWalking()
        walkTargetX = min(maxX, max(minX, target))
        let goingLeft = walkTargetX < current

        // A walk/ folder is a real walk cycle; walk1 + walk2 is a simple two-step shuffle.
        var cycle = frames(named: cycleName)
        currentSpeed = speed ?? walkSpeed
        let pace = legPace ?? Double(currentSpeed / walkSpeed)
        var interval = 1 / charFPS / pace
        if cycle.isEmpty {
            cycle = frames(named: "walk1") + frames(named: "walk2")
            interval = 0.27 / pace
        }
        if cycle.isEmpty {
            // Only one still: keep it facing the viewer and fake the steps with a waddle.
            play(frames(for: .idle), every: interval)
            waddle()
        } else {
            let facesRight = cycleName == "run" ? charRunFacesRight : charWalkFacesRight
            play(goingLeft == facesRight ? cycle.map(mirrored) : cycle, every: interval)
        }

        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.stepWalk()
        }
    }

    func stepWalk() {
        guard let panel else { return }
        var origin = panel.frame.origin
        let step = currentSpeed / 30
        if abs(walkTargetX - origin.x) <= step {
            origin.x = walkTargetX
            panel.setFrameOrigin(origin)
            setMood(.idle)      // also stops the walk
            UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "origin")
            return
        }
        origin.x += walkTargetX > origin.x ? step : -step
        panel.setFrameOrigin(origin)
    }

    func stopWalking() {
        walkTimer?.invalidate()
        walkTimer = nil
        buddy.layer?.removeAnimation(forKey: "waddle")
        buddy.layer?.removeAnimation(forKey: "step")
    }

    /// Side-to-side rock plus a little hop on each step, pivoting at the feet.
    func waddle() {
        let rock = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rock.values = [0, 0.07, 0, -0.07, 0]
        rock.duration = 0.7
        rock.repeatCount = .infinity
        buddy.layer?.add(rock, forKey: "waddle")
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 7, 0]
        hop.duration = 0.35
        hop.repeatCount = .infinity
        hop.isAdditive = true
        buddy.layer?.add(hop, forKey: "step")
    }

    func jump() {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
        a.values = [0, 30, 0, 12, 0]
        a.keyTimes = [0, 0.35, 0.6, 0.8, 1]
        a.duration = 0.7
        a.isAdditive = true
        buddy.layer?.add(a, forKey: "jump")
    }

    // MARK: animation

    func startBobbing() {
        let a = CABasicAnimation(keyPath: "transform.translation.y")
        a.fromValue = 0; a.toValue = 6
        a.duration = 1.4; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        buddy.layer?.add(a, forKey: "bob")
    }

    func shake() {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -10, 10, -8, 8, -4, 4, 0]
        a.duration = 0.5
        buddy.layer?.add(a, forKey: "shake")
    }

    // MARK: speech

    func say(_ text: String, for seconds: Double? = 8, buttons: [(String, () -> Void)] = []) {
        let h = bubble.show(text, buttons: buttons, width: 250)
        bubble.frame = NSRect(x: 5, y: 198, width: 250, height: min(150, h))
        bubble.isHidden = false
        bubbleTimer?.invalidate()
        if let seconds {
            bubbleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                self?.bubble.isHidden = true
                if self?.waitingForWater == false { self?.setMood(.idle) }
            }
        }
    }

    // MARK: water

    func waterReminder() {
        if isMinimized { restoreBro { [weak self] in self?.waterReminder() }; return }
        waitingForWater = true
        setMood(.water)
        say(String(format: waterLines.randomElement()!, config.userName), for: nil, buttons: [
            ("YES", { [weak self] in self?.drankWater() }),
            ("Remind me later", { [weak self] in self?.snoozeWater() }),
        ])
        NSSound(named: "Glass")?.play()
    }

    func snoozeWater() {
        waitingForWater = false
        setMood(.warn)        // sad face: plays the whole clip, then back to normal when the bubble goes
        say("Okay bro… 10 more minutes. Don't forget me 🥺", for: 6)
        Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in self?.waterReminder() }
    }

    func drankWater() {
        waitingForWater = false
        waterCountToday += 1
        setMood(.happy)
        // 1) the cheer, standing still
        let cheer = 2.5
        say("\(thanksLines.randomElement()!) That's \(waterCountToday) glass\(waterCountToday == 1 ? "" : "es") today.", for: cheer)
        // 2) then the text goes and he runs (but stays put beside the chat if it's open)
        DispatchQueue.main.asyncAfter(deadline: .now() + cheer + 0.15) { [weak self] in
            guard let self, self.chatPanel?.isVisible != true, !self.isAttacking, !self.waitingForWater,
                  let screen = self.panel.screen?.visibleFrame else { return }
            self.bubbleTimer?.invalidate()
            self.bubble.isHidden = true
            let x = self.panel.frame.midX > screen.midX ? screen.minX + 40 : screen.maxX - self.panel.frame.width - 40
            self.run(to: x)
        }
    }

    func clicked() {
        if waitingForWater { drankWater(); return }
        swag()
    }

    // MARK: browser watch

    func checkBrowsers() {
        if isAttacking { return }
        let now = Date()

        // A final warning was issued: close when the countdown runs out, even if they switched tabs.
        if let at = finalWarningAt, now >= at {
            finalWarningAt = nil
            closeNow()
            return
        }

        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              let browser = browsers.first(where: { $0.bundleID == front }) else {
            resetIfOnBreak(now); return
        }

        let (url, err) = activeURL(of: browser)
        caughtIn = browser
        // one-line status for troubleshooting: what Bro last saw
        try? "\(Date()) \(browser.name) url=\(url ?? "-") err=\(err.map(String.init) ?? "none") budget=\(sessionBudget.map { "\(Int($0))s" } ?? "none") spent=\(Int(distractedSeconds))s\n"
            .write(to: supportDir.appendingPathComponent("watch-status.txt"), atomically: true, encoding: .utf8)
        if let err, err == -1743, !permissionWarned {
            permissionWarned = true
            if isMinimized { restoreBro(then: {}) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.permissionWarned = false }
            setMood(.warn)
            say("I can't see \(browser.name) yet. Allow me in System Settings → Privacy & Security → Automation.", for: 15)
        }
        guard let url, let site = config.distractingSites.first(where: { url.contains($0) }) else {
            resetIfOnBreak(now); return
        }

        let base = site.components(separatedBy: ".").first ?? site
        let siteName = ["youtube": "YouTube", "instagram": "Instagram", "facebook": "Facebook", "x": "X",
                        "netflix": "Netflix", "reddit": "Reddit", "linkedin": "LinkedIn", "primevideo": "Prime Video",
                        "hotstar": "Hotstar", "jiocinema": "JioCinema", "sonyliv": "SonyLIV", "zee5": "ZEE5",
                        "disneyplus": "Disney+", "aha": "aha", "sunnxt": "Sun NXT"][base.lowercased()] ?? base.capitalized

        lastDistracted = now
        if config.askBudget && sessionBudget == nil {
            if !askingBudget { askForBudget(siteName) }
            return                                  // the clock starts once he's answered
        }
        distractedSeconds += pollInterval
        let mins = Int(distractedSeconds / 60)
        updateStatusTitle()

        let spent = distractedSeconds < 60 ? "\(Int(distractedSeconds)) sec" : "\(mins) min"
        let budget = sessionBudget ?? config.closeAfterMinutes * 60
        let warning = sessionBudget == nil ? config.warningSeconds : min(config.warningSeconds, budget / 3)
        let nagAt = sessionBudget == nil ? config.nagAfterMinutes * 60 : budget / 3
        let nagEvery = sessionBudget == nil ? config.nagRepeatSeconds : max(5, budget / 6)
        if finalWarningAt == nil && distractedSeconds >= budget - warning {
            if isMinimized { restoreBro(then: {}) }
            finalWarningAt = now.addingTimeInterval(warning)
            setMood(.angry)
            NSSound(named: "Sosumi")?.play()
            let line = angryLines.randomElement()!
            say(String(format: line, siteName, spent, Int(warning)), for: warning)
        } else if finalWarningAt == nil && distractedSeconds >= nagAt
                    && (lastNag == 0 || distractedSeconds - lastNag >= nagEvery) {
            if isMinimized { restoreBro(then: {}) }
            lastNag = distractedSeconds
            setMood(.warn)
            NSSound(named: "Tink")?.play()
            let line = nagLines.randomElement()!
            say(String(format: line, siteName, spent), for: 10)
        }
    }

    func resetIfOnBreak(_ now: Date) {
        if finalWarningAt == nil && now.timeIntervalSince(lastDistracted) >= config.breakResetMinutes * 60 {
            distractedSeconds = 0
            lastNag = 0
            sessionBudget = nil         // next visit asks again
            updateStatusTitle()
        }
    }

    static func label(minutes m: Double) -> String {
        if m < 1 { return "\(Int((m * 60).rounded())) sec" }
        if m >= 60 { return m == 60 ? "1 hr" : String(format: "%g hr", m / 60) }
        return "\(Int(m)) min"
    }

    /// Pops up (even when minimised) and asks how long he wants; the first option is used if he doesn't answer.
    func askForBudget(_ siteName: String) {
        askingBudget = true
        if isMinimized { restoreBro { [weak self] in self?.presentBudgetQuestion(siteName) }; return }
        presentBudgetQuestion(siteName)
    }

    func presentBudgetQuestion(_ siteName: String) {
        stopWalking()
        setMood(.idle)
        var options = config.budgetOptionsMinutes.isEmpty ? [config.closeAfterMinutes] : config.budgetOptionsMinutes
        let fallback = config.defaultBudgetMinutes ?? options[0]       // picked if he doesn't answer
        if !options.contains(fallback) { options = (options + [fallback]).sorted() }
        let question = "Hey \(config.userName)! How much time do you need on \(siteName)?"
        say(question, for: nil, buttons: options.map { m in (Self.label(minutes: m), { [weak self] in self?.setBudget(m, siteName) }) })
        NSSound(named: "Pop")?.play()
        if voiceEnabled && config.voiceReplies { speaker.say("Hey bro! How much time do you need on \(siteName)?", then: nil) }
        let token = UUID()
        askToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.askingBudget, self.askToken == token else { return }
            self.setBudget(fallback, siteName, auto: true)
        }
    }

    func setBudget(_ minutes: Double, _ siteName: String, auto: Bool = false) {
        askingBudget = false
        askToken = nil
        sessionBudget = minutes * 60
        distractedSeconds = 0
        lastNag = 0
        speaker.stop()
        if auto {
            say("No answer? \(Self.label(minutes: minutes)) it is ⏱", for: 2)
        } else {
            bubbleTimer?.invalidate()           // picked a time: the question vanishes straight away
            bubble.isHidden = true
        }
        updateStatusTitle()
        // then he gets out of the way until it's time to nag
        DispatchQueue.main.asyncAfter(deadline: .now() + (auto ? 2 : 0)) { [weak self] in
            guard let self, self.sessionBudget != nil, self.finalWarningAt == nil else { return }
            self.minimize(quiet: true)
        }
    }

    // MARK: minimise / menu bar

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "😎"
        let m = NSMenu()
        m.addItem(withTitle: "Show / hide Bro", action: #selector(toggleMinimized), keyEquivalent: "").target = self
        m.addItem(withTitle: "Chat with Bro 💬", action: #selector(menuChat), keyEquivalent: "").target = self
        m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Bro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = m
        statusItem = item
    }

    /// Menu-bar icon shows the time left in the current session.
    func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        if let budget = sessionBudget {
            let left = max(0, Int(budget - distractedSeconds))
            button.title = String(format: "😎 %d:%02d", left / 60, left % 60)
        } else {
            button.title = "😎"
        }
    }

    @objc func toggleMinimized() { isMinimized ? showBro() : minimizeBro() }

    /// Where he flies to when minimised: the 😎 menu-bar icon (or the Dock if there's no icon).
    var minimizeTarget: NSPoint {
        if let w = statusItem?.button?.window { return NSPoint(x: w.frame.midX, y: w.frame.midY) }
        let s = NSScreen.main?.frame ?? .zero
        return NSPoint(x: s.midX, y: s.minY)
    }

    /// Moves the window along a curve while scaling him (feet-anchored) and fading.
    func fly(from a: NSPoint, to b: NSPoint, scale: (CGFloat, CGFloat), alpha: (CGFloat, CGFloat),
             duration: Double, easeIn: Bool, onStep: ((NSPoint) -> Void)? = nil, done: @escaping () -> Void) {
        hopTimer?.invalidate()
        let start = Date()
        hopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let k = min(1, Date().timeIntervalSince(start) / duration)
            let e = easeIn ? k * k * k : 1 - pow(1 - k, 3)
            // a little sideways swoop on the way
            let swoop = CGFloat(sin(k * .pi)) * 60 * (b.x > a.x ? -1 : 1)
            self.panel.setFrameOrigin(NSPoint(x: a.x + (b.x - a.x) * e + swoop, y: a.y + (b.y - a.y) * e))
            let sc = scale.0 + (scale.1 - scale.0) * e
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.buddy.layer?.setAffineTransform(CGAffineTransform(scaleX: sc, y: sc)
                .rotated(by: CGFloat(sin(k * .pi * 2)) * 0.25 * (1 - e)))
            CATransaction.commit()
            self.panel.alphaValue = alpha.0 + (alpha.1 - alpha.0) * e
            onStep?(self.bodyCenter(scale: sc))
            if k >= 1 { t.invalidate(); done() }
        }
    }

    var homeOrigin = NSPoint.zero

    /// Middle of his body on screen, given the current scale (he scales from his feet).
    func bodyCenter(scale: CGFloat = 1) -> NSPoint {
        NSPoint(x: panel.frame.minX + buddy.frame.midX, y: panel.frame.minY + buddy.frame.minY + buddy.frame.height * scale * 0.5)
    }

    /// Waves bye, then shrinks and flies up into the menu-bar icon. He lives there (and in the Dock)
    /// until clicked, or until YouTube/OTT or a water reminder brings him back.
    @objc func minimizeBro() { minimize(quiet: false) }

    /// `quiet`: skip the goodbye line and vanish straight away (used after he picks a time).
    func minimize(quiet: Bool) {
        guard !isMinimized, !isAttacking else { return }
        isMinimized = true
        stopWalking()
        closeChat()
        homeOrigin = panel.frame.origin
        if !quiet {
            setMood(.happy)
            say("Bye bro! I'll be up here 👆", for: 1.3)
            NSSound(named: "Pop")?.play()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0.05 : 1.3)) { [weak self] in
            guard let self, self.isMinimized else { return }
            self.bubble.isHidden = true
            let target = self.minimizeTarget
            let end = NSPoint(x: target.x - self.panel.frame.width / 2, y: target.y - self.buddy.frame.height * 0.12)
            // wind-up: puff up a little before vanishing
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            self.buddy.layer?.setAffineTransform(CGAffineTransform(scaleX: 1.18, y: 0.9))
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            let fx = EffectsLayer(below: self.panel)
            fx.poof(at: self.bodyCenter())
            fx.startTrail(at: self.bodyCenter())
            NSSound(named: "Blow")?.play()
            self.fly(from: self.homeOrigin, to: end, scale: (1.18, 0.06), alpha: (1, 0.1), duration: 0.6, easeIn: true,
                     onStep: { fx.trail(to: $0) }) {
                fx.stopTrail()
                fx.poof(at: target, size: 0.35)
                NSSound(named: "Pop")?.play()
                fx.finish()
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.buddy.layer?.setAffineTransform(.identity)
                NSApp.setActivationPolicy(.regular)          // Dock icon to click him back
                if let face = self.image(for: .idle).flatMap(faceCrop) { NSApp.applicationIconImage = face }
                self.statusItem?.button?.title = "😎💤"
            }
            }
        }
    }

    /// Drops out of the menu-bar icon, grows back with a bounce, lands with the hello swag.
    @objc func showBro() { restoreBro(then: nil) }

    /// `then` runs once he has landed (instead of the hello greeting), e.g. the question that called him back.
    func restoreBro(then: (() -> Void)?) {
        guard isMinimized else { then?(); return }
        isMinimized = false
        NSApp.setActivationPolicy(.accessory)
        updateStatusTitle()
        let target = minimizeTarget
        let from = NSPoint(x: target.x - panel.frame.width / 2, y: target.y - buddy.frame.height * 0.12)
        let home = homeOrigin == .zero ? panel.frame.origin : homeOrigin
        panel.alphaValue = 0.15
        buddy.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.08, y: 0.08))
        panel.setFrameOrigin(from)
        panel.orderFrontRegardless()
        NSSound(named: "Pop")?.play()
        let fx = EffectsLayer(below: panel)
        fx.poof(at: target, size: 0.35)
        fx.startTrail(at: target)
        fly(from: from, to: home, scale: (0.08, 1.08), alpha: (0.15, 1), duration: 0.7, easeIn: false,
            onStep: { fx.trail(to: $0) }) { [weak self] in
            guard let self else { return }
            fx.stopTrail()
            fx.poof(at: self.bodyCenter())
            NSSound(named: "Blow")?.play()
            fx.finish()
            // settle from slightly too big back to normal: a small landing bounce
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            self.buddy.layer?.setAffineTransform(.identity)
            CATransaction.commit()
            self.smash()
            if let then { then() } else { self.sayHello() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showBro()                                            // clicking the Dock icon brings him back
        return false
    }

    var caughtIn: Browser?
    var isAttacking = false
    var hopTimer: Timer?
    var burstWindow: NSPanel?

    func closeNow() {
        let close = { [weak self] in
            guard let self else { return }
            for b in browsers where NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID).count > 0 {
                closeDistracting(in: b, sites: self.config.distractingSites, mode: self.config.closeMode)
            }
            self.distractedSeconds = 0
            self.lastNag = 0
            self.sessionBudget = nil
            self.updateStatusTitle()
        }
        let scold = { [weak self] in
            self?.setMood(.angry)
            self?.say("Closed. Go stretch, drink some water, look at something far away. 🌳", for: 12)
        }
        if let b = caughtIn, let tab = activeTabPoint(of: b) {
            attackTab(at: tab, close: close, done: scold)
        } else {
            close(); scold()
        }
    }

    @objc func practiceSmash() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let tab = browsers.first(where: { $0.bundleID == front }).flatMap(activeTabPoint)
            ?? NSPoint(x: (NSScreen.main?.frame.midX ?? 700), y: (NSScreen.main?.visibleFrame.maxY ?? 800) - 20)
        attackTab(at: tab, close: {}, done: { [weak self] in self?.say("That's what happens to your reels. 😤", for: 5) })
    }

    /// Leap up to the tab, smash it (closing it on impact), hop back home.
    func attackTab(at tab: NSPoint, close: @escaping () -> Void, done: @escaping () -> Void) {
        isAttacking = true
        if let chat = chatPanel { panel.removeChildWindow(chat) }
        stopWalking()
        bubble.isHidden = true
        bubbleTimer?.invalidate()
        let home = panel.frame.origin
        // top of his head just under the tab
        let target = NSPoint(x: tab.x - panel.frame.width / 2, y: tab.y - buddy.frame.maxY - 2)
        let goingLeft = target.x < home.x
        let leap = frames(named: "walk").dropFirst(8).first ?? image(for: .idle)
        if let leap { play([goingLeft == charWalkFacesRight ? mirrored(leap) : leap], every: 1) }
        NSSound(named: "Purr")?.play()

        hop(from: home, to: target, arc: 140, duration: 0.85) { [weak self] in
            guard let self else { return }
            self.play(self.frames(for: .angry), every: 1 / self.charFPS, loop: false)
            self.smash()
            self.burst(at: tab)
            NSSound(named: "Funk")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: close)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let leap { self.play([goingLeft == self.charWalkFacesRight ? leap : self.mirrored(leap)], every: 1) }
                self.hop(from: target, to: home, arc: 70, duration: 0.8) {
                    self.isAttacking = false
                    if let chat = self.chatPanel, chat.isVisible { self.panel.addChildWindow(chat, ordered: .above) }
                    self.shake()
                    done()
                }
            }
        }
    }

    func hop(from a: NSPoint, to b: NSPoint, arc: CGFloat, duration: Double, done: @escaping () -> Void) {
        hopTimer?.invalidate()
        let start = Date()
        hopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            let k = min(1, Date().timeIntervalSince(start) / duration)
            let x = a.x + (b.x - a.x) * k
            let y = a.y + (b.y - a.y) * k + arc * 4 * k * (1 - k)   // parabola on top of the straight line
            self?.panel.setFrameOrigin(NSPoint(x: x, y: y))
            if k >= 1 { t.invalidate(); done() }
        }
    }

    /// A quick upward punch of the whole body.
    func smash() {
        let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
        a.values = [0, 22, -4, 0]
        a.keyTimes = [0, 0.3, 0.7, 1]
        a.duration = 0.35
        a.isAdditive = true
        buddy.layer?.add(a, forKey: "smash")
    }

    /// 💥 over the tab that grows and fades.
    func burst(at p: NSPoint) {
        let size: CGFloat = 140
        let w = NSPanel(contentRect: NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let label = NSTextField(labelWithString: "💥")
        label.font = .systemFont(ofSize: 90)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 10, width: size, height: size - 20)
        w.contentView = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        w.contentView?.addSubview(label)
        w.alphaValue = 1
        w.orderFrontRegardless()
        burstWindow = w
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.9
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            w.orderOut(nil)
            if self?.burstWindow === w { self?.burstWindow = nil }
        })
    }

    // MARK: menu

    func showMenu(_ event: NSEvent) {
        let m = NSMenu()
        m.addItem(withTitle: "Chat with Bro 💬", action: #selector(menuChat), keyEquivalent: "").target = self
        m.addItem(withTitle: "Clear chat 🗑", action: #selector(clearChat), keyEquivalent: "").target = self
        m.addItem(withTitle: "Minimise Bro ⤵︎", action: #selector(minimizeBro), keyEquivalent: "").target = self
        if isShareBuild {
            let ai = m.addItem(withTitle: AIChat.isConfigured(config) ? "Agentic chat: on ✓" : "Agentic chat… (add API key)",
                               action: #selector(openSettings), keyEquivalent: "")
            ai.target = self
        } else {
            let sv = m.addItem(withTitle: "Use Sarvam voice & chat", action: #selector(menuSarvamToggle), keyEquivalent: "")
            sv.target = self
            sv.state = useSarvam ? .on : .off
            m.addItem(withTitle: Sarvam.apiKey == nil ? "Set Sarvam API key…" : "Change Sarvam API key…",
                      action: #selector(menuSarvamKey), keyEquivalent: "").target = self
        }
        m.addItem(.separator())
        let tidy = NSMenuItem(title: "Tidy a folder 🧹", action: nil, keyEquivalent: "")
        let tm = NSMenu()
        tm.addItem(withTitle: "Tidy Downloads", action: #selector(menuTidyDownloads), keyEquivalent: "").target = self
        tm.addItem(withTitle: "Tidy Desktop", action: #selector(menuTidyDesktop), keyEquivalent: "").target = self
        tm.addItem(withTitle: "Choose a folder…", action: #selector(menuTidyChoose), keyEquivalent: "").target = self
        tm.addItem(.separator())
        tm.addItem(withTitle: "Undo last tidy", action: #selector(menuUndoTidy), keyEquivalent: "").target = self
        tidy.submenu = tm
        m.addItem(tidy)
        m.addItem(.separator())
        m.addItem(withTitle: "I drank water 💧", action: #selector(menuDrank), keyEquivalent: "").target = self
        m.addItem(withTitle: "Remind me to drink now", action: #selector(menuRemind), keyEquivalent: "").target = self
        m.addItem(.separator())
        let chars = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for c in characters {
            let item = sub.addItem(withTitle: displayName(c), action: #selector(menuCharacter(_:)), keyEquivalent: "")
            item.representedObject = c
            item.target = self
            item.state = c == config.character ? .on : .off
        }
        chars.submenu = sub
        m.addItem(chars)
        m.addItem(withTitle: "Open stickers folder…", action: #selector(menuStickers), keyEquivalent: "").target = self
        m.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        if !isShareBuild {
            m.addItem(withTitle: "Edit settings file…", action: #selector(menuSettings), keyEquivalent: "").target = self
        }
        m.addItem(withTitle: "Show tutorial", action: #selector(startTutorial), keyEquivalent: "").target = self
        let roam = m.addItem(withTitle: "Walk around", action: #selector(menuWalking), keyEquivalent: "")
        roam.target = self
        roam.state = config.walking ? .on : .off
        m.addItem(withTitle: "Walk left ←", action: #selector(menuWalkLeft), keyEquivalent: "").target = self
        m.addItem(withTitle: "Walk right →", action: #selector(menuWalkRight), keyEquivalent: "").target = self
        m.addItem(withTitle: "Practice smash (closes nothing)", action: #selector(practiceSmash), keyEquivalent: "").target = self
        let login = m.addItem(withTitle: "Start at login", action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Bro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        NSMenu.popUpContextMenu(m, with: event, for: buddy)
    }

    @objc func menuDrank() { drankWater() }
    @objc func menuChat() { openChat(listen: false) }
    @objc func menuSarvamToggle() {
        if Sarvam.apiKey == nil { menuSarvamKey(); return }
        config.useSarvam.toggle()
        saveConfig(config)
        say(config.useSarvam ? (voiceEnabled ? "Sarvam voice on 🇮🇳" : "AI chat on") : (voiceEnabled ? "Back to the Mac voice" : "Offline mode"), for: 3)
    }
    @objc func menuSarvamKey() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Sarvam API key"
        alert.informativeText = "Paste your key from dashboard.sarvam.ai. It's saved only on this Mac."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "sk_…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Sarvam.saveKey(key)
        config.useSarvam = true
        saveConfig(config)
        buddySays(voiceEnabled ? "Sarvam is connected. Now I sound like a proper Chennai boy!" : "AI chat is on. Double-click me to talk!")
    }
    @objc func menuWalking() {
        config.walking.toggle()
        saveConfig(config)
        if !config.walking && isWalking { setMood(.idle) }
    }
    @objc func menuWalkLeft() { walk(to: panel.frame.origin.x - 400) }
    @objc func menuWalkRight() { walk(to: panel.frame.origin.x + 400) }
    @objc func menuRemind() { waterReminder() }
    @objc func menuCharacter(_ item: NSMenuItem) {
        switchCharacter(item.representedObject as? String ?? item.title)
    }
    @objc func menuStickers() { NSWorkspace.shared.open(stickersDir) }
    @objc func menuSettings() {
        NSWorkspace.shared.open(configURL)
        say("Edit the file, save it, then quit and reopen me.", for: 6)
    }
    @objc func menuLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            say("Couldn't change login item: \(error.localizedDescription)", for: 6)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
