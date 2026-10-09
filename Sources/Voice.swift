import AVFoundation
import Speech

/// Push-to-talk speech recognition. Stops on its own after a short pause.
final class Listener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")) ?? SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var transcript = ""
    private var completion: ((String?) -> Void)?

    var onPartial: ((String) -> Void)?
    var isListening: Bool { completion != nil }

    /// Calls `done` with what was said, or nil if permission was refused / nothing was heard.
    func start(done: @escaping (String?) -> Void) {
        guard !isListening else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { done(nil); return }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async { granted ? self.begin(done) : done(nil) }
                }
            }
        }
    }

    func stop() { finish() }

    private func begin(_ done: @escaping (String?) -> Void) {
        guard let recognizer, recognizer.isAvailable else { done(nil); return }
        completion = done
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { finish(); return }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isListening else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.onPartial?(self.transcript)
                    self.armSilence(1.4)          // stop once they pause
                    if result.isFinal { self.finish() }
                } else if error != nil {
                    self.finish()
                }
            }
        }
        armSilence(7)                             // give up if nothing is said
    }

    private func armSilence(_ seconds: Double) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.finish() }
    }

    private func finish() {
        silenceTimer?.invalidate()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        let done = completion
        completion = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        done?(text.isEmpty ? nil : text)
    }
}

/// Text-to-speech for Buddy's replies.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var finished: (() -> Void)?
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices()
        // Prefer a good-quality Indian English male voice, then any English voice.
        let ranked = all.filter { $0.language.hasPrefix("en") }.sorted { a, b in
            func score(_ v: AVSpeechSynthesisVoice) -> Int {
                (v.language == "en-IN" ? 4 : 0) + (v.gender == .male ? 2 : 0) + (v.quality == .default ? 0 : 1)
            }
            return score(a) > score(b)
        }
        return ranked.first
    }()

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, then: (() -> Void)? = nil) {
        // emoji get read out loud ("face with steam from nose…"), so strip them
        let clean = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2300))
        }))
        synth.stopSpeaking(at: .immediate)
        finished = then
        let u = AVSpeechUtterance(string: clean)
        u.voice = voice
        u.rate = 0.5
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let f = finished
        finished = nil
        f?()
    }
}
