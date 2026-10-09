import AVFoundation
import Foundation

/// Sarvam AI (api.sarvam.ai): chat, speech-to-text and text-to-speech tuned for Indian voices and languages.
enum Sarvam {
    static var keyURL: URL { supportDir.appendingPathComponent("sarvam.key") }

    static var apiKey: String? {
        let saved = (try? String(contentsOf: keyURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return ProcessInfo.processInfo.environment["SARVAM_API_KEY"]
    }

    static func saveKey(_ key: String) {
        try? key.trimmingCharacters(in: .whitespacesAndNewlines).write(to: keyURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    }

    private static func request(_ path: String) -> URLRequest? {
        guard let key = apiKey, let url = URL(string: "https://api.sarvam.ai" + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 40
        r.setValue(key, forHTTPHeaderField: "api-subscription-key")
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return r
    }

    private static func send(_ r: URLRequest, done: @escaping ([String: Any]?, String?) -> Void) {
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            var problem: String?
            if let err { problem = err.localizedDescription }
            else if status != 200 {
                let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data ?? Data(), encoding: .utf8) ?? ""
                problem = "Sarvam \(status): \(msg.prefix(200))"
            }
            DispatchQueue.main.async { done(problem == nil ? json : nil, problem) }
        }.resume()
    }

    /// OpenAI-style chat. Returns the assistant text (reasoning stripped) or an error.
    static func chat(messages: [[String: String]], model: String, done: @escaping (String?, String?) -> Void) {
        guard var r = request("/v1/chat/completions") else { return done(nil, "No Sarvam API key") }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "temperature": 0.7, "max_tokens": 600,
        ] as [String: Any])
        send(r) { json, err in
            guard let choices = json?["choices"] as? [[String: Any]],
                  var text = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
                return done(nil, err ?? "Sarvam sent an empty reply")
            }
            if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
            done(text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
    }

    /// Text-to-speech. Returns WAV audio.
    static func speak(_ text: String, language: String, speaker: String, done: @escaping (Data?, String?) -> Void) {
        guard var r = request("/text-to-speech") else { return done(nil, "No Sarvam API key") }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": String(text.prefix(2400)), "language_code": language, "speaker": speaker,
            "model": "bulbul:v3", "pace": 1.05, "speech_sample_rate": 24000, "output_audio_codec": "wav",
        ] as [String: Any])
        send(r) { json, err in
            guard let b64 = (json?["audios"] as? [String])?.first, let audio = Data(base64Encoded: b64) else {
                return done(nil, err ?? "Sarvam sent no audio")
            }
            done(audio, nil)
        }
    }

    /// Speech-to-text with automatic language detection (English, Tamil, Hindi, code-mixed…).
    static func transcribe(wav: URL, done: @escaping (String?, String?) -> Void) {
        guard var r = request("/speech-to-text"), let audio = try? Data(contentsOf: wav) else {
            return done(nil, "No Sarvam API key")
        }
        let boundary = "buddy-\(UUID().uuidString)"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "saaras:v3")
        field("mode", "codemix")
        field("language_code", "unknown")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        r.httpBody = body
        send(r) { json, err in done(json?["transcript"] as? String, err) }
    }

    /// Picks the TTS language from the script the reply is written in.
    static func language(of text: String) -> String {
        for s in text.unicodeScalars {
            switch s.value {
            case 0x0B80...0x0BFF: return "ta-IN"
            case 0x0900...0x097F: return "hi-IN"
            case 0x0C00...0x0C7F: return "te-IN"
            case 0x0C80...0x0CFF: return "kn-IN"
            case 0x0D00...0x0D7F: return "ml-IN"
            default: continue
            }
        }
        return "en-IN"
    }
}

// MARK: - Ears & mouth protocols (Mac built-in or Sarvam)

protocol Ears: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var isListening: Bool { get }
    func start(done: @escaping (String?) -> Void)
    func stop()
}

protocol Mouth: AnyObject {
    func say(_ text: String, then: (() -> Void)?)
    func stop()
}

extension Listener: Ears {}
extension Speaker: Mouth {}

/// Records until you stop talking, then sends the audio to Sarvam for transcription.
final class SarvamListener: Ears {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var completion: ((String?) -> Void)?
    private var started = Date()
    private var lastVoice: Date?
    private var checkTimer: Timer?
    private let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("buddy-speech.wav")
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    var onPartial: ((String) -> Void)?
    var isListening: Bool { completion != nil }

    func start(done: @escaping (String?) -> Void) {
        guard !isListening else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { granted ? self.begin(done) : done(nil) }
        }
    }

    func stop() { finish(send: true) }

    private func begin(_ done: @escaping (String?) -> Void) {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let conv = AVAudioConverter(from: inFormat, to: target) else { done(nil); return }
        converter = conv
        try? FileManager.default.removeItem(at: wavURL)
        file = try? AVAudioFile(forWriting: wavURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file != nil else { done(nil); return }

        completion = done
        started = Date()
        lastVoice = nil
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { finish(send: false); return }
        onPartial?("🔴 Listening…")
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.checkSilence() }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        // loudness, to know when they've stopped talking
        if let ch = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            if rms > 0.02 { DispatchQueue.main.async { self.lastVoice = Date() } }
        }
        guard let converter, let out = AVAudioPCMBuffer(pcmFormat: target,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 32) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        try? file?.write(from: out)
    }

    private func checkSilence() {
        let now = Date()
        if let last = lastVoice {
            if now.timeIntervalSince(last) > 1.2 || now.timeIntervalSince(started) > 20 { finish(send: true) }
        } else if now.timeIntervalSince(started) > 7 {
            finish(send: false)            // nothing was said
        }
    }

    private func finish(send: Bool) {
        guard let done = completion else { return }
        completion = nil
        checkTimer?.invalidate()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        file = nil                          // closes the WAV
        guard send, lastVoice != nil else { done(nil); return }
        onPartial?("✍️ Understanding…")
        Sarvam.transcribe(wav: wavURL) { text, err in
            if let err { NSLog("Buddy STT: \(err)") }
            let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            done(t.isEmpty ? nil : t)
        }
    }
}

/// Speaks with a Sarvam Bulbul voice; falls back to the Mac voice if Sarvam fails.
final class SarvamSpeaker: NSObject, Mouth, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finished: (() -> Void)?
    private let fallback: Mouth
    private let voice: () -> String
    private var generation = 0

    init(fallback: Mouth, voice: @escaping () -> String) {
        self.fallback = fallback
        self.voice = voice
    }

    func say(_ text: String, then: (() -> Void)?) {
        stop()
        generation += 1
        let mine = generation
        let clean = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2300))
        }))
        Sarvam.speak(clean, language: Sarvam.language(of: clean), speaker: voice()) { [weak self] audio, err in
            guard let self, mine == self.generation else { return }      // a newer line replaced this one
            guard let audio, let p = try? AVAudioPlayer(data: audio) else {
                NSLog("Buddy TTS: \(err ?? "bad audio")")
                self.fallback.say(clean, then: then)
                return
            }
            self.finished = then
            p.delegate = self
            self.player = p
            p.play()
        }
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        finished = nil
        fallback.stop()
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) {
        let f = finished
        finished = nil
        f?()
    }
}
