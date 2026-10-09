import AppKit

// MARK: - Brain (Claude CLI)

struct BrainReply {
    let reply: String
    let action: [String: Any]?
}

func findClaude() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "\(home)/.claude/local/claude"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

func askClaude(system: String, prompt: String, model: String, done: @escaping (BrainReply) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let fail = { (msg: String) in DispatchQueue.main.async { done(BrainReply(reply: msg, action: nil)) } }
        guard let claude = findClaude() else { return fail("I can't find the claude command on this Mac, so I can't think right now.") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        // Minimal system prompt, no tools, no project/user settings: fast and cheap.
        p.arguments = ["-p", "--model", model, "--setting-sources", "", "--tools", "", "--strict-mcp-config",
                       "--system-prompt", system, "--output-format", "json", prompt]
        p.currentDirectoryURL = supportDir
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice     // otherwise claude waits for stdin
        do { try p.run() } catch { return fail("My brain didn't start: \(error.localizedDescription)") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = wrapper["result"] as? String else {
            return fail("Hmm, my brain glitched. Is Claude Code logged in?")
        }
        DispatchQueue.main.async { done(parseBrain(result)) }
    }
}

/// The model sometimes wraps its JSON in ``` fences or adds chatter; take the outermost {...}.
func parseBrain(_ result: String) -> BrainReply {
    if let a = result.firstIndex(of: "{"), let b = result.lastIndex(of: "}"), a < b,
       let obj = try? JSONSerialization.jsonObject(with: Data(result[a...b].utf8)) as? [String: Any],
       let reply = obj["reply"] as? String {
        return BrainReply(reply: reply, action: obj["action"] as? [String: Any])
    }
    return BrainReply(reply: result, action: nil)
}

// MARK: - Conversation

extension AppDelegate {
    var systemPrompt: String {
        """
        You are Bro, \(config.userName)'s cheeky but caring 3D cartoon companion who lives on his Mac screen. \
        You remind him to drink water and kick him off YouTube/Instagram when he doomscrolls. \
        Talk like his close friend: simple, warm English. Call him \"bro\" naturally. \
        Never use \"da\", \"machan\", \"macha\", \"dei\" or \"mate\". \
        Your replies are spoken aloud: keep them to 1-2 short, playful sentences. No markdown, no emoji. \
        Reply in the language he uses: English, Tamil (in Tamil script), or Tanglish.
        You can also act on his Mac. Respond ONLY with JSON:
        {"reply": string, "action": null | {"type":"tidy","folder":string} | {"type":"undo_tidy"} | {"type":"drank_water"} | {"type":"walk","direction":"left"|"right"}}
        - tidy: he wants a folder cleaned/organised/sorted/tidied. folder = "Downloads", "Desktop", "Documents" or a path. \
        Your reply should say you'll take a look; the app counts the files and asks him to confirm.
        - undo_tidy: he wants the last tidy undone / files put back.
        - drank_water: he says he drank water.
        - walk: he asks you to move or walk somewhere.
        Facts: he has had \(waterCountToday) glasses of water today; time on distracting sites right now: \(Int(distractedSeconds / 60)) min.
        """
    }

    func toggleChat() {
        if let chat = chatPanel, chat.isVisible { closeChat(); return }
        openChat(listen: voiceEnabled && config.voiceFirst)
    }

    func openChat(listen: Bool) {
        if chatPanel == nil {
            let c = ChatPanel(userName: config.userName)
            c.onSend = { [weak self] text in self?.userSaid(text) }
            c.onMic = { [weak self] in self?.toggleListening() }
            c.onClose = { [weak self] in self?.closeChat() }
            c.onClear = { [weak self] in self?.clearChat() }
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: c, queue: .main) {
                [weak self] _ in self?.chatMoved()
            }
            chatPanel = c
            c.setAvatar(image(for: .idle))
            c.add("Bro", greeting)
        }
        guard let chat = chatPanel else { return }
        // sit beside Buddy, on whichever side has room
        let f = panel.frame
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        // Buddy is narrower than his window, so tuck the chat into the empty margin beside him.
        let margin: CGFloat = 55
        var x = f.minX - chat.frame.width + margin
        if x < screen.minX { x = f.maxX - margin }
        chat.setFrameOrigin(NSPoint(x: x, y: max(screen.minY, f.minY)))
        stopWalking()
        setMood(.idle)
        NSApp.activate(ignoringOtherApps: true)
        chat.makeKeyAndOrderFront(nil)
        // Buddy and the chat move as one: drag either and the other follows.
        chatOffset = NSPoint(x: panel.frame.minX - chat.frame.minX, y: panel.frame.minY - chat.frame.minY)
        panel.addChildWindow(chat, ordered: .above)
        chat.makeFirstResponder(chat.input)
        if listen { startListening() }
    }

    var greeting: String {
        if isShareBuild && !AIChat.isConfigured(config) {
            return "Hey \(config.userName)! I can tidy folders (\"tidy my downloads\"), undo a tidy, log water or walk around. Turn on Agentic chat in Settings for a real conversation."
        }
        return "Hey \(config.userName)! Ask me anything, or say something like \"tidy my downloads folder\"."
    }

    /// Fresh start (handy before a demo): no messages, no memory of the conversation, nothing pending.
    @objc func clearChat() {
        listener.stop()
        speaker.stop()
        chatHistory.removeAll()
        pendingTidy = nil
        chatPanel?.setListening(false)
        chatPanel?.clearMessages()
        chatPanel?.add("Bro", greeting)
        setMood(.idle)
    }

    func closeChat() {
        listener.stop()
        speaker.stop()
        if let chat = chatPanel { panel.removeChildWindow(chat) }
        chatPanel?.orderOut(nil)
    }

    /// The chat window was dragged: bring Buddy along (child windows only follow their parent, not the reverse).
    func chatMoved() {
        guard !syncingChat, !isAttacking, let chat = chatPanel, chat.isVisible else { return }
        let want = NSPoint(x: chat.frame.minX + chatOffset.x, y: chat.frame.minY + chatOffset.y)
        guard abs(want.x - panel.frame.minX) > 0.5 || abs(want.y - panel.frame.minY) > 0.5 else { return }
        syncingChat = true
        panel.removeChildWindow(chat)
        panel.setFrameOrigin(want)
        panel.addChildWindow(chat, ordered: .above)
        UserDefaults.standard.set(NSStringFromPoint(want), forKey: "origin")
        syncingChat = false
    }

    func toggleListening() {
        listener.isListening ? listener.stop() : startListening()
    }

    func startListening() {
        guard voiceEnabled else { return }
        speaker.stop()
        chatPanel?.setListening(true)
        setMood(.idle)
        listener.onPartial = { [weak self] text in self?.chatPanel?.input.stringValue = text }
        listener.start { [weak self] text in
            guard let self else { return }
            self.chatPanel?.setListening(false)
            if let text { self.userSaid(text) }
        }
    }

    func buddySays(_ text: String, mood: Mood = .happy, thenListen: Bool = false) {
        chatPanel?.add("Bro", text)
        let chatting = chatPanel?.isVisible == true
        if !chatting { say(text, for: 8) }
        setMood(chatting && mood == .happy ? .idle : mood)
        chatHistory.append("Bro: \(text)")
        guard voiceEnabled && config.voiceReplies else { if thenListen { startListening() }; return }
        speaker.say(text) { [weak self] in
            if thenListen, self?.chatPanel?.isVisible == true { self?.startListening() }
        }
    }

    func userSaid(_ text: String) {
        chatPanel?.add(config.userName, text)

        // A yes/no for a pending tidy is handled here, without asking the model.
        if let plan = pendingTidy {
            let t = text.lowercased()
            let yes = ["yes", "yeah", "yep", "sure", "ok", "okay", "do it", "go ahead", "go for it", "please"].contains { t.contains($0) }
            let no = ["no", "nope", "cancel", "stop", "don't", "wait", "leave it"].contains { t.contains($0) }
            if yes && !no {
                pendingTidy = nil
                runTidy(plan)
                return
            } else if no {
                pendingTidy = nil
                buddySays("Okay, I won't touch anything.", mood: .idle)
                return
            }
            pendingTidy = nil
        }

        chatHistory.append("\(config.userName): \(text)")
        let convo = chatHistory.suffix(12).joined(separator: "\n")
        chatPanel?.showTyping()
        let finish: (BrainReply) -> Void = { [weak self] r in
            self?.chatPanel?.hideTyping()
            self?.handle(r)
        }
        if AIChat.isConfigured(config) {
            // agentic chat with the person's own API key (any provider)
            let history = chatHistory.suffix(12).map { line -> (String, String) in
                let isBro = line.hasPrefix("Bro: ")
                return (isBro ? "assistant" : "user", line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces))
            }
            let typed = text
            AIChat.send(system: systemPrompt, history: Array(history), config: config) { answer, err in
                if let answer { finish(parseBrain(answer)); return }
                NSLog("Bro agentic chat: \(err ?? "?")")
                var r = offlineBrain(typed)               // keep working offline if the API call fails
                if r.action == nil { r = BrainReply(reply: "My chat API didn't answer (\(err ?? "unknown error")). Check the key in Settings.", action: nil) }
                finish(r)
            }
        } else if useSarvam {
            var messages = [["role": "system", "content": systemPrompt]]
            for line in chatHistory.suffix(12) {
                let isBuddy = line.hasPrefix("Bro: ")
                let text = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                messages.append(["role": isBuddy ? "assistant" : "user", "content": text])
            }
            let typed = text
            Sarvam.chat(messages: messages, model: config.sarvamChatModel) { [weak self] answer, err in
                guard let self else { return }
                if let answer { finish(parseBrain(answer)); return }
                NSLog("Buddy chat: \(err ?? "?")")
                // Sarvam hiccup: keep the conversation going (offline commands in the share build, Claude otherwise)
                if isShareBuild { finish(offlineBrain(typed)) }
                else { askClaude(system: self.systemPrompt, prompt: convo, model: self.config.chatModel, done: finish) }
            }
        } else if isShareBuild {
            // no AI key: plain pattern matching, no internet
            let reply = offlineBrain(text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { finish(reply) }
        } else {
            askClaude(system: systemPrompt, prompt: convo, model: config.chatModel, done: finish)
        }
    }

    func handle(_ r: BrainReply) {
        switch r.action?["type"] as? String {
        case "tidy":
            let name = r.action?["folder"] as? String ?? "Downloads"
            guard let folder = Tidy.resolve(name) else {
                buddySays("I couldn't find a folder called \(name).", mood: .warn); return
            }
            do {
                let plan = try Tidy.plan(folder)
                if plan.moves.isEmpty {
                    buddySays("\(folder.lastPathComponent) is already tidy. Nothing loose to sort!"); return
                }
                pendingTidy = plan          // the model's own line may claim it's already done, so skip it
                buddySays("In \(folder.lastPathComponent) I found \(plan.summary). Shall I sort them into folders?",
                          mood: .water, thenListen: true)
            } catch {
                buddySays("macOS won't let me look in \(folder.lastPathComponent) yet. Click OK on the permission popup, or allow me under Privacy & Security → Files and Folders.", mood: .warn)
            }
        case "undo_tidy":
            if let n = Tidy.undoLast() { buddySays("Done, I put \(n) files back where they were.") }
            else { buddySays("There's no tidy for me to undo.", mood: .idle) }
        case "drank_water":
            waitingForWater = false
            waterCountToday += 1
            buddySays(r.reply + " That's \(waterCountToday) today.")
        case "walk":
            buddySays(r.reply)
            walk(to: panel.frame.origin.x + ((r.action?["direction"] as? String) == "left" ? -400 : 400))
        default:
            buddySays(r.reply)
        }
    }

    func runTidy(_ plan: TidyPlan) {
        let (moved, failed) = Tidy.apply(plan)
        var text = "All done! I moved \(moved) files in \(plan.folder.lastPathComponent) into folders."
        if failed > 0 { text += " \(failed) wouldn't budge." }
        text += " Say \"undo\" if you want them back."
        buddySays(text)
        NSWorkspace.shared.open(plan.folder)
    }
}
