import AppKit
import ServiceManagement

/// Known sites/OTT platforms shown as checkboxes in Settings (title, domains matched in the tab URL).
let knownSites: [(String, [String])] = [
    ("YouTube", ["youtube.com"]), ("Instagram", ["instagram.com"]), ("Facebook", ["facebook.com"]),
    ("X / Twitter", ["x.com", "twitter.com"]), ("Reddit", ["reddit.com"]), ("Netflix", ["netflix.com"]),
    ("Prime Video", ["primevideo.com"]), ("JioHotstar", ["hotstar.com"]), ("JioCinema", ["jiocinema.com"]),
    ("SonyLIV", ["sonyliv.com"]), ("ZEE5", ["zee5.com"]), ("Disney+", ["disneyplus.com"]),
    ("aha", ["aha.video"]), ("Sun NXT", ["sunnxt.com"]),
]

private final class TopAlignedView: NSView {
    override var isFlipped: Bool { true }
}

/// Settings window: everything people would otherwise edit in config.json.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private weak var app: AppDelegate?
    private let name = NSTextField()
    private let character = NSPopUpButton()
    private var characterFolders: [String] = []
    private let water = NSTextField()
    private let walking = NSButton(checkboxWithTitle: "Walk around the screen", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Start Bro when I log in", target: nil, action: nil)
    private var siteBoxes: [(NSButton, [String])] = []
    private let otherSites = NSTextField()
    private let ask = NSButton(checkboxWithTitle: "Ask how much time I need when I open one", target: nil, action: nil)
    private let choices = NSTextField()
    private let defaultTime = NSTextField()
    private let closeAfter = NSTextField()
    private let provider = NSPopUpButton()
    private let apiKey = NSSecureTextField()
    private let model = NSTextField()
    private let baseURL = NSTextField()
    private let keyNote = NSTextField(labelWithString: "")

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Bro Settings"
        w.isReleasedWhenClosed = false
        w.level = .floating
        super.init(window: w)
        w.delegate = self
        build()
        load()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: layout helpers

    private func header(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = Denim.mid
        return l
    }

    private func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func row(_ label: String, _ field: NSView, _ suffix: String? = nil, width: CGFloat = 220) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: 170).isActive = true
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        var views: [NSView] = [l, field]
        if let suffix { views.append(NSTextField(labelWithString: suffix)) }
        let s = NSStackView(views: views)
        s.spacing = 8
        return s
    }

    private func build() {
        guard let w = window else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)

        // You
        stack.addArrangedSubview(header("You"))
        stack.addArrangedSubview(row("Character", character))
        stack.addArrangedSubview(row("Bro calls you", name))
        stack.addArrangedSubview(row("Water reminder every", water, "minutes", width: 60))
        stack.addArrangedSubview(walking)
        stack.addArrangedSubview(login)

        // Sites
        stack.addArrangedSubview(header("Sites & OTT apps to watch"))
        let grid = NSGridView(numberOfColumns: 3, rows: 0)
        grid.columnSpacing = 18
        grid.rowSpacing = 6
        var rowViews: [NSView] = []
        for (title, domains) in knownSites {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            siteBoxes.append((b, domains))
            rowViews.append(b)
            if rowViews.count == 3 { grid.addRow(with: rowViews); rowViews = [] }
        }
        if !rowViews.isEmpty {
            while rowViews.count < 3 { rowViews.append(NSView()) }
            grid.addRow(with: rowViews)
        }
        stack.addArrangedSubview(grid)
        otherSites.placeholderString = "e.g. twitch.tv, linkedin.com"
        stack.addArrangedSubview(row("Other sites", otherSites, nil, width: 300))

        // Time
        stack.addArrangedSubview(header("Screen time"))
        stack.addArrangedSubview(ask)
        choices.placeholderString = "5, 15, 30, 60"
        stack.addArrangedSubview(row("Time choices", choices, "minutes", width: 160))
        stack.addArrangedSubview(row("Default if I don't answer", defaultTime, "minutes", width: 60))
        stack.addArrangedSubview(row("If not asking, close after", closeAfter, "minutes", width: 60))

        // Agentic chat
        stack.addArrangedSubview(header("Agentic chat (optional)"))
        stack.addArrangedSubview(note("Bro tidies folders, times your sites and reminds you to drink water without any AI. "
            + "Add your own chat API key to have real conversations with him. The key is stored only on this Mac."))
        for p in AIProvider.allCases { provider.addItem(withTitle: p.title) }
        provider.target = self
        provider.action = #selector(providerChanged)
        stack.addArrangedSubview(row("Provider", provider, nil, width: 240))
        apiKey.placeholderString = "Paste your API key"
        stack.addArrangedSubview(row("API key", apiKey, nil, width: 300))
        stack.addArrangedSubview(row("Model", model, nil, width: 240))
        baseURL.placeholderString = "https://…/v1"
        stack.addArrangedSubview(row("Base URL (Other)", baseURL, nil, width: 300))
        keyNote.font = .systemFont(ofSize: 11)
        keyNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(keyNote)

        // Buttons
        let tutorial = NSButton(title: "Show tutorial", target: self, action: #selector(showTutorial))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [tutorial, spacer, cancel, save])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        let doc = TopAlignedView()           // flipped, so the form starts at the top
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        w.contentView = scroll
    }

    // MARK: values

    private func minutesText(_ m: Double) -> String { m == m.rounded() ? String(Int(m)) : String(m) }

    private func load() {
        guard let c = app?.config else { return }
        name.stringValue = c.userName
        characterFolders = app?.characters ?? []
        character.removeAllItems()
        for f in characterFolders { character.addItem(withTitle: app?.displayName(f) ?? f) }
        character.selectItem(at: characterFolders.firstIndex(of: c.character) ?? 0)
        water.stringValue = minutesText(c.waterIntervalMinutes)
        walking.state = c.walking ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        var covered = Set<String>()
        for (box, domains) in siteBoxes {
            let on = domains.contains { c.distractingSites.contains($0) }
            box.state = on ? .on : .off
            covered.formUnion(domains)
        }
        otherSites.stringValue = c.distractingSites.filter { !covered.contains($0) }.joined(separator: ", ")
        ask.state = c.askBudget ? .on : .off
        choices.stringValue = c.budgetOptionsMinutes.map(minutesText).joined(separator: ", ")
        defaultTime.stringValue = minutesText(c.defaultBudgetMinutes ?? c.budgetOptionsMinutes.first ?? 15)
        closeAfter.stringValue = minutesText(c.closeAfterMinutes)
        let p = AIChat.provider(c)
        provider.selectItem(at: AIProvider.allCases.firstIndex(of: p) ?? 0)
        model.stringValue = c.aiModel.isEmpty ? p.defaultModel : c.aiModel
        baseURL.stringValue = c.aiBaseURL
        refreshChatFields()
    }

    private func refreshChatFields() {
        let p = AIProvider.allCases[max(0, provider.indexOfSelectedItem)]
        let on = p != .off
        apiKey.isEnabled = on
        model.isEnabled = on
        baseURL.isEnabled = p == .custom
        if AIChat.apiKey != nil {
            apiKey.placeholderString = "•••••••• saved (leave empty to keep)"
            keyNote.stringValue = on ? "A key is saved on this Mac. Choose \"Off\" and Save to remove it." : "Saved key will be removed when you Save."
        } else {
            apiKey.placeholderString = "Paste your API key"
            keyNote.stringValue = on ? "Get a key from your provider's dashboard, then paste it here." : ""
        }
    }

    @objc private func providerChanged() {
        let p = AIProvider.allCases[max(0, provider.indexOfSelectedItem)]
        if !p.defaultModel.isEmpty { model.stringValue = p.defaultModel }
        refreshChatFields()
    }

    private func minutes(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    @objc private func saveTapped() {
        guard let app else { return }
        var c = app.config
        let n = name.stringValue.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { c.userName = n }
        if let m = minutes(water.stringValue), m >= 1 { c.waterIntervalMinutes = m }
        c.walking = walking.state == .on

        var sites: [String] = []
        for (box, domains) in siteBoxes where box.state == .on { sites += domains }
        sites += otherSites.stringValue.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.lowercased().replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "www.", with: "") }
            .filter { $0.contains(".") }
        c.distractingSites = Array(NSOrderedSet(array: sites)) as? [String] ?? sites

        c.askBudget = ask.state == .on
        let opts = choices.stringValue.split(separator: ",").compactMap { minutes(String($0)) }.filter { $0 > 0 }
        if !opts.isEmpty { c.budgetOptionsMinutes = Array(Set(opts)).sorted() }
        if let d = minutes(defaultTime.stringValue), d > 0 { c.defaultBudgetMinutes = d }
        if let m = minutes(closeAfter.stringValue), m > 0 { c.closeAfterMinutes = m }

        let p = AIProvider.allCases[max(0, provider.indexOfSelectedItem)]
        c.aiProvider = p.rawValue
        c.aiModel = model.stringValue.trimmingCharacters(in: .whitespaces)
        c.aiBaseURL = baseURL.stringValue.trimmingCharacters(in: .whitespaces)
        let key = apiKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if p == .off { AIChat.removeKey() } else if !key.isEmpty { AIChat.saveKey(key) }

        do {
            if login.state == .on && SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            if login.state == .off && SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch { NSLog("Bro login item: \(error)") }

        let picked = characterFolders.indices.contains(character.indexOfSelectedItem) ? characterFolders[character.indexOfSelectedItem] : c.character
        let switched = picked != app.config.character
        app.apply(c)
        if switched { app.switchCharacter(picked) }
        close()
    }

    @objc private func cancelTapped() { close() }

    @objc private func showTutorial() {
        close()
        app?.startTutorial()
    }

    func show() {
        load()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Applying settings, tutorial

extension AppDelegate {
    @objc func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(app: self) }
        settingsWindow?.show()
    }

    /// Saves and applies new settings straight away (no restart needed).
    func apply(_ c: Config) {
        let waterChanged = c.waterIntervalMinutes != config.waterIntervalMinutes
        config = c
        saveConfig(c)
        if waterChanged { restartWaterTimer() }
        if !c.walking && isWalking { setMood(.idle) }
        setMood(.happy)
        say("Saved! 👍", for: 2)
    }

    func restartWaterTimer() {
        waterTimer?.invalidate()
        waterTimer = Timer.scheduledTimer(withTimeInterval: config.waterIntervalMinutes * 60, repeats: true) { [weak self] _ in
            self?.waterReminder()
        }
    }

    var tutorialSteps: [String] {
        [
            "Hey \(config.userName)! I'm \(displayName(config.character)), your desktop buddy 👋",
            "Double-click me to chat. Single-click for my swag move. Drag me anywhere you like.",
            "I can tidy your Downloads, your Desktop, or any folder you pick. Right-click me → Tidy a folder, or just tell me in chat.",
            "I watch YouTube, Instagram and OTT apps. When you open one, I'll ask how much time you need, and close it when time's up ⏱",
            "Want a different buddy? Right-click me → Character and pick \(characters.filter { $0 != config.character }.map { displayName($0) }.joined(separator: ", ")). You can also change it in Settings 🎭",
            "I'll remind you to drink water every \(Int(config.waterIntervalMinutes)) minutes 💧",
            "Change anything in Settings: right-click me → Settings. Want real AI chat? Add your API key there. Let's go!",
        ]
    }

    @objc func startTutorial() {
        if isMinimized { restoreBro { [weak self] in self?.startTutorial() }; return }
        tutorialStep = 0
        stopWalking()
        showTutorialStep()
    }

    func showTutorialStep() {
        let steps = tutorialSteps
        guard tutorialStep < steps.count else { return }
        let last = tutorialStep == steps.count - 1
        setMood(tutorialStep == 0 ? .happy : .idle)
        var buttons: [(String, () -> Void)] = [(last ? "Got it 👍" : "Next →", { [weak self] in self?.nextTutorialStep() })]
        if last { buttons.insert(("Open Settings", { [weak self] in self?.finishTutorial(); self?.openSettings() }), at: 0) }
        else { buttons.append(("Skip", { [weak self] in self?.finishTutorial() })) }
        say("\(steps[tutorialStep])  (\(tutorialStep + 1)/\(steps.count))", for: nil, buttons: buttons)
    }

    func nextTutorialStep() {
        tutorialStep += 1
        if tutorialStep >= tutorialSteps.count { finishTutorial() } else { showTutorialStep() }
    }

    func finishTutorial() {
        bubbleTimer?.invalidate()
        bubble.isHidden = true
        config.tutorialDone = true
        saveConfig(config)
        setMood(.happy)
    }
}
