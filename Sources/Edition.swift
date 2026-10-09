import AppKit

// Two editions from one codebase:
//   personal (default)       voice chat, Claude CLI fallback, your own settings
//   share  (-D SHARE_BUILD)  for giving away: no voice at all, no keys, works fully offline;
//                            AI chat is opt-in with the person's own Sarvam key.
#if SHARE_BUILD
let voiceEnabled = false
let isShareBuild = true
let appSupportName = "Bro"
#else
let voiceEnabled = true
let isShareBuild = false
let appSupportName = "DesktopBuddy"
#endif

/// First name of whoever is logged in to this Mac ("Friend" if it can't be found).
let macFirstName: String = {
    let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    return first.isEmpty ? "Friend" : first
}()

// MARK: - Offline brain (no AI, no internet)

/// Understands Bro's handful of commands with plain pattern matching, so tidy / undo / water / walk
/// all work without any API key.
func offlineBrain(_ text: String) -> BrainReply {
    let t = " " + text.lowercased() + " "
    func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }

    if has(["undo", "put them back", "put it back", "put my files back", "revert"]) {
        return BrainReply(reply: "Okay bro, putting things back.", action: ["type": "undo_tidy"])
    }
    if has(["tidy", "clean", "organis", "organiz", "sort", "arrange", "declutter"]) {
        var folder = "Downloads"
        for name in ["downloads", "desktop", "documents", "pictures", "movies", "music"] where t.contains(name) {
            folder = name.capitalized
        }
        // a typed path wins: "tidy ~/Projects/stuff"
        if let path = text.split(separator: " ").first(where: { $0.hasPrefix("/") || $0.hasPrefix("~") }) {
            folder = String(path)
        }
        return BrainReply(reply: "Let me take a look.", action: ["type": "tidy", "folder": folder])
    }
    if has(["drank", "had water", "had some water", "drink done", "hydrated", "had a glass"]) {
        return BrainReply(reply: "Nice one, bro!", action: ["type": "drank_water"])
    }
    if has(["walk", "move", "go "]) && has(["left", "right"]) {
        return BrainReply(reply: "On my way!", action: ["type": "walk", "direction": t.contains("left") ? "left" : "right"])
    }
    if has([" hi ", " hey ", "hello", " yo ", "sup", "how are you"]) {
        return BrainReply(reply: "Hey bro! I'm running offline, so I know a few tricks: tidy a folder, undo a tidy, log water, or walk left or right. Turn on Agentic chat in my Settings for a proper conversation.", action: nil)
    }
    return BrainReply(reply: "I'm in offline mode, bro. Try \"tidy my downloads\", \"undo\", \"I drank water\" or \"walk left\". For real chat, right-click me → Settings → Agentic chat.", action: nil)
}

// MARK: - Tidy from the menu (no chat needed)

extension AppDelegate {
    @objc func menuTidyDownloads() { tidyWithConfirm(Tidy.resolve("downloads")) }
    @objc func menuTidyDesktop() { tidyWithConfirm(Tidy.resolve("desktop")) }

    @objc func menuTidyChoose() {
        NSApp.activate(ignoringOtherApps: true)
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.allowsMultipleSelection = false
        open.prompt = "Tidy this folder"
        open.message = "Bro sorts the loose files in this folder into Images, Videos, Audio, Documents and Archives."
        if open.runModal() == .OK { tidyWithConfirm(open.url) }
    }

    @objc func menuUndoTidy() {
        if let n = Tidy.undoLast() { setMood(.happy); say("Done, \(n) files are back where they were.", for: 5) }
        else { say("There's no tidy for me to undo.", for: 4) }
    }

    /// Counts what would move, asks once, then sorts. Pure file moves: no AI involved.
    func tidyWithConfirm(_ folder: URL?) {
        guard let folder else { say("I couldn't find that folder.", for: 4); return }
        let plan: TidyPlan
        do { plan = try Tidy.plan(folder) } catch {
            setMood(.warn)
            say("macOS won't let me look in \(folder.lastPathComponent) yet. Allow me when it asks, then try again.", for: 8)
            return
        }
        if plan.moves.isEmpty { say("\(folder.lastPathComponent) is already tidy!", for: 4); return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Tidy \(folder.lastPathComponent)?"
        alert.informativeText = "Bro found \(plan.summary).\n\nThey'll be moved into Images, Videos, Audio, Documents and Archives folders inside \(folder.lastPathComponent). Nothing is deleted, and you can undo it from Bro's menu."
        alert.addButton(withTitle: "Tidy it")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let (moved, failed) = Tidy.apply(plan)
        setMood(.happy)
        say("Moved \(moved) files into folders" + (failed > 0 ? " (\(failed) wouldn't budge)" : "") + ". Undo is in my menu.", for: 6)
        NSWorkspace.shared.open(folder)
    }

    @objc func menuChangeName() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "What should Bro call you?"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = config.userName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        config.userName = name
        saveConfig(config)
        setMood(.happy)
        say("Hey, \(name)! 👋", for: 4)
    }
}
