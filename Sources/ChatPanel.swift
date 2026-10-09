import AppKit
import Vision

/// The chat window, styled like Buddy's outfit: denim twill, gold jean stitching, a leather patch and copper rivets.
enum Denim {
    static let deep = NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.31, alpha: 1)
    static let mid = NSColor(calibratedRed: 0.17, green: 0.29, blue: 0.48, alpha: 1)
    static let faded = NSColor(calibratedRed: 0.40, green: 0.53, blue: 0.73, alpha: 1)
    static let thread = NSColor(calibratedRed: 0.91, green: 0.69, blue: 0.29, alpha: 1)
    static let leather = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.17, alpha: 1)
    static let leatherDark = NSColor(calibratedRed: 0.40, green: 0.24, blue: 0.11, alpha: 1)
    static let cream = NSColor(calibratedRed: 0.97, green: 0.91, blue: 0.79, alpha: 1)
    static let tee = NSColor(calibratedRed: 0.89, green: 0.89, blue: 0.90, alpha: 1)
    static let copperLight = NSColor(calibratedRed: 0.93, green: 0.64, blue: 0.36, alpha: 1)
    static let copperDark = NSColor(calibratedRed: 0.62, green: 0.33, blue: 0.13, alpha: 1)

    /// Diagonal twill weave as a repeating pattern.
    static let twill: NSColor = {
        let img = NSImage(size: NSSize(width: 6, height: 6), flipped: false) { r in
            mid.setFill()
            r.fill()
            let light = NSBezierPath()
            for o in stride(from: -6, through: 6, by: 6) {
                light.move(to: NSPoint(x: CGFloat(o), y: 0))
                light.line(to: NSPoint(x: CGFloat(o) + 6, y: 6))
            }
            light.lineWidth = 1.4
            NSColor(white: 1, alpha: 0.07).setStroke()
            light.stroke()
            let dark = NSBezierPath()
            for o in stride(from: -3, through: 9, by: 6) {
                dark.move(to: NSPoint(x: CGFloat(o), y: 0))
                dark.line(to: NSPoint(x: CGFloat(o) + 6, y: 6))
            }
            dark.lineWidth = 1
            NSColor(white: 0, alpha: 0.12).setStroke()
            dark.stroke()
            return true
        }
        return NSColor(patternImage: img)
    }()

    /// Dashed "stitch" outline following a rounded rect.
    static func stitch(_ rect: CGRect, radius: CGFloat, color: NSColor = thread, width: CGFloat = 1.5) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        l.fillColor = nil
        l.strokeColor = color.cgColor
        l.lineWidth = width
        l.lineDashPattern = [5, 3.5]
        l.lineCap = .round
        return l
    }

    static func rivet(at p: CGPoint) -> CALayer {
        let g = CAGradientLayer()
        g.frame = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
        g.type = .radial
        g.colors = [copperLight.cgColor, copperDark.cgColor]
        g.startPoint = CGPoint(x: 0.35, y: 0.65)
        g.endPoint = CGPoint(x: 1, y: 0)
        g.cornerRadius = 5
        g.borderColor = NSColor(white: 0, alpha: 0.35).cgColor
        g.borderWidth = 0.5
        return g
    }
}

/// Square crop around the face (macOS Vision), or the top-centre if no face is found.
func faceCrop(_ img: NSImage) -> NSImage? {
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let W = CGFloat(cg.width), H = CGFloat(cg.height)
    var crop: CGRect
    let req = VNDetectFaceRectanglesRequest()
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    if let face = req.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox {
        let f = CGRect(x: face.minX * W, y: face.minY * H, width: face.width * W, height: face.height * H)
        let side = max(f.width, f.height) * 1.9
        crop = CGRect(x: f.midX - side / 2, y: f.midY - side / 2 - f.height * 0.05, width: side, height: side)
    } else {
        let side = W * 0.62
        crop = CGRect(x: (W - side) / 2, y: H - side * 1.05, width: side, height: side)
    }
    crop = crop.intersection(CGRect(x: 0, y: 0, width: W, height: H))
    let sx = img.size.width / W, sy = img.size.height / H
    let src = CGRect(x: crop.minX * sx, y: crop.minY * sy, width: crop.width * sx, height: crop.height * sy)
    return NSImage(size: NSSize(width: 256, height: 256), flipped: false) { r in
        NSBezierPath(ovalIn: r).addClip()
        img.draw(in: r, from: src, operation: .sourceOver, fraction: 1)
        return true
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A round copper button with an SF Symbol in it.
final class CopperButton: NSView {
    var action: (() -> Void)?
    private let gradient = CAGradientLayer()
    private let icon = NSImageView()

    init(symbol: String, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        gradient.frame = bounds
        gradient.cornerRadius = size / 2
        gradient.borderWidth = 1.5
        gradient.borderColor = Denim.thread.withAlphaComponent(0.8).cgColor
        layer?.addSublayer(gradient)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        icon.frame = bounds.insetBy(dx: size * 0.27, dy: size * 0.27)
        icon.contentTintColor = .white
        icon.symbolConfiguration = .init(pointSize: size * 0.4, weight: .bold)
        addSubview(icon)
        set(symbol: symbol, hot: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(symbol: String, hot: Bool) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        gradient.colors = hot
            ? [NSColor.systemRed.blended(withFraction: 0.2, of: .white)!.cgColor, NSColor(calibratedRed: 0.65, green: 0.1, blue: 0.12, alpha: 1).cgColor]
            : [Denim.copperLight.cgColor, Denim.copperDark.cgColor]
        layer?.removeAnimation(forKey: "pulse")
        if hot {
            layer?.shadowColor = NSColor.systemRed.cgColor
            let a = CABasicAnimation(keyPath: "shadowRadius")
            a.fromValue = 3; a.toValue = 14
            a.duration = 0.7; a.autoreverses = true; a.repeatCount = .infinity
            layer?.shadowOpacity = 0.9
            layer?.add(a, forKey: "pulse")
        } else {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.35
            layer?.shadowRadius = 4
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { alphaValue = 0.75 }
    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
    }
}

/// One chat message. Buddy's are faded denim on the left, yours are t-shirt grey on the right.
private final class BubbleRow: NSView {
    let label: NSTextField

    init(text: String, mine: Bool) {
        label = NSTextField(wrappingLabelWithString: text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let bg = NSView()
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 15
        bg.layer?.backgroundColor = (mine ? Denim.tee : Denim.faded).cgColor
        bg.layer?.borderWidth = mine ? 0 : 1
        bg.layer?.borderColor = Denim.thread.withAlphaComponent(0.55).cgColor
        bg.layer?.shadowOpacity = 0.25
        bg.layer?.shadowRadius = 2
        bg.layer?.shadowOffset = CGSize(width: 0, height: -1)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13.5, weight: .medium)
        label.textColor = mine ? NSColor(calibratedWhite: 0.13, alpha: 1) : .white
        label.isSelectable = true
        label.preferredMaxLayoutWidth = 214
        bg.addSubview(label)
        addSubview(bg)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bg.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -12),
            bg.topAnchor.constraint(equalTo: topAnchor),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
            mine ? bg.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
                 : bg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    let input = NSTextField()
    var onSend: ((String) -> Void)?
    var onMic: (() -> Void)?
    var onClose: (() -> Void)?
    var onClear: (() -> Void)?

    private let W: CGFloat = 340, H: CGFloat = 470
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let status = NSTextField(labelWithString: "")
    private let avatar = NSImageView()
    private let mic = CopperButton(symbol: "mic.fill", size: 44)
    private var typingRow: NSView?
    private let userName: String

    init(userName: String) {
        self.userName = userName
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 470),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        build()
    }

    private func build() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        root.wantsLayer = true
        guard let base = root.layer else { return }
        base.cornerRadius = 24
        base.masksToBounds = true
        base.backgroundColor = Denim.twill.cgColor

        // depth: lighter at the top like worn denim, darker at the hem
        let shade = CAGradientLayer()
        shade.frame = root.bounds
        shade.colors = [NSColor(white: 1, alpha: 0.10).cgColor, NSColor.clear.cgColor, Denim.deep.withAlphaComponent(0.55).cgColor]
        shade.locations = [0, 0.45, 1]
        shade.startPoint = CGPoint(x: 0.5, y: 1)
        shade.endPoint = CGPoint(x: 0.5, y: 0)
        base.addSublayer(shade)

        // jean seams
        base.addSublayer(Denim.stitch(root.bounds.insetBy(dx: 7, dy: 7), radius: 19))
        let seam = CAShapeLayer()
        let seamPath = CGMutablePath()
        for y in [H - 82, H - 86] as [CGFloat] {
            seamPath.move(to: CGPoint(x: 12, y: y))
            seamPath.addLine(to: CGPoint(x: W - 12, y: y))
        }
        seam.path = seamPath
        seam.strokeColor = Denim.thread.withAlphaComponent(0.85).cgColor
        seam.lineWidth = 1.3
        seam.lineDashPattern = [5, 3.5]
        base.addSublayer(seam)
        for p in [CGPoint(x: 22, y: H - 22), CGPoint(x: W - 22, y: H - 22), CGPoint(x: 22, y: H - 84), CGPoint(x: W - 22, y: H - 84)] {
            base.addSublayer(Denim.rivet(at: p))
        }

        // avatar in a copper ring
        avatar.frame = NSRect(x: 34, y: H - 74, width: 50, height: 50)
        avatar.wantsLayer = true
        avatar.imageScaling = .scaleAxesIndependently
        avatar.layer?.cornerRadius = 25
        avatar.layer?.masksToBounds = true
        avatar.layer?.borderWidth = 2.5
        avatar.layer?.borderColor = Denim.thread.cgColor
        avatar.layer?.backgroundColor = Denim.cream.cgColor
        root.addSubview(avatar)

        // leather patch with the name
        let patch = NSView(frame: NSRect(x: 94, y: H - 50, width: 118, height: 30))
        patch.wantsLayer = true
        let leather = CAGradientLayer()
        leather.frame = patch.bounds
        leather.colors = [Denim.leather.cgColor, Denim.leatherDark.cgColor]
        leather.cornerRadius = 6
        patch.layer?.addSublayer(leather)
        patch.layer?.addSublayer(Denim.stitch(patch.bounds.insetBy(dx: 3, dy: 3), radius: 4, color: Denim.cream.withAlphaComponent(0.8), width: 1))
        patch.layer?.shadowOpacity = 0.4
        patch.layer?.shadowRadius = 2
        patch.layer?.shadowOffset = CGSize(width: 0, height: -1)
        let name = NSTextField(labelWithString: "BRO")
        name.font = NSFont(name: "AvenirNext-Heavy", size: 15) ?? .systemFont(ofSize: 15, weight: .black)
        name.textColor = Denim.cream
        name.alignment = .center
        name.frame = NSRect(x: 0, y: 5, width: 118, height: 20)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        name.shadow = shadow
        patch.addSubview(name)
        root.addSubview(patch)

        status.frame = NSRect(x: 96, y: H - 72, width: 200, height: 16)
        status.font = .systemFont(ofSize: 11, weight: .semibold)
        root.addSubview(status)
        setStatus(listening: false)

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")!,
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = NSColor(white: 1, alpha: 0.6)
        close.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        close.frame = NSRect(x: W - 52, y: H - 58, width: 26, height: 26)
        root.addSubview(close)

        let clear = NSButton(image: NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Clear chat")!,
                             target: self, action: #selector(clearTapped))
        clear.isBordered = false
        clear.contentTintColor = NSColor(white: 1, alpha: 0.6)
        clear.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        clear.toolTip = "Clear chat"
        clear.frame = NSRect(x: W - 82, y: H - 58, width: 26, height: 26)
        root.addSubview(clear)

        // messages
        scroll.frame = NSRect(x: 14, y: 80, width: W - 28, height: H - 80 - 96)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        root.addSubview(scroll)

        // input pill with a stitched edge
        let pill = NSView(frame: NSRect(x: 16, y: 20, width: voiceEnabled ? W - 32 - 54 : W - 32, height: 44))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        pill.layer?.cornerRadius = 22
        pill.layer?.addSublayer(Denim.stitch(pill.bounds.insetBy(dx: 3, dy: 3), radius: 19, color: Denim.thread.withAlphaComponent(0.7), width: 1.2))
        input.frame = NSRect(x: 16, y: 12, width: pill.frame.width - 30, height: 20)
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.font = .systemFont(ofSize: 14, weight: .medium)
        input.textColor = .white
        input.target = self
        input.action = #selector(sendTapped)
        setPlaceholder(idlePlaceholder)
        pill.addSubview(input)
        root.addSubview(pill)

        mic.frame.origin = NSPoint(x: W - 16 - 46, y: 20)
        mic.action = { [weak self] in self?.onMic?() }
        if voiceEnabled { root.addSubview(mic) }       // the share build has no voice

        contentView = root
    }

    private var idlePlaceholder: String {
        voiceEnabled ? "Type, or tap the mic and talk…" : "Type… e.g. \"tidy my downloads\""
    }

    private func setPlaceholder(_ text: String) {
        input.placeholderAttributedString = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor(white: 1, alpha: 0.55), .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        ])
    }

    private func setStatus(listening: Bool) {
        let dot = listening ? "🔴" : "🟢"
        status.stringValue = listening ? "\(dot) listening…" : "\(dot) online · Chennai vibes"
        status.textColor = listening ? NSColor(calibratedRed: 1, green: 0.75, blue: 0.75, alpha: 1) : Denim.cream.withAlphaComponent(0.85)
    }

    /// Profile picture: the character's face, found with macOS Vision.
    func setAvatar(_ img: NSImage?) {
        avatar.image = img.flatMap(faceCrop)
    }

    @objc private func sendTapped() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input.stringValue = ""
        onSend?(text)
    }
    @objc private func closeTapped() { onClose?() }
    @objc private func clearTapped() { onClear?() }

    /// Removes every message bubble.
    func clearMessages() {
        typingRow = nil
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        input.stringValue = ""
    }

    func add(_ who: String, _ text: String) {
        hideTyping()
        append(BubbleRow(text: text, mine: who != "Bro"))
    }

    func showTyping() {
        hideTyping()
        let row = BubbleRow(text: "• • •", mine: false)
        row.label.font = .systemFont(ofSize: 15, weight: .heavy)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 0.3
        a.duration = 0.6; a.autoreverses = true; a.repeatCount = .infinity
        row.wantsLayer = true
        row.layer?.add(a, forKey: "typing")
        typingRow = row
        append(row)
    }

    func hideTyping() {
        typingRow?.removeFromSuperview()
        typingRow = nil
    }

    private func append(_ row: NSView) {
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        contentView?.layoutSubtreeIfNeeded()
        if let doc = scroll.documentView {
            let y = max(0, doc.frame.height - scroll.contentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    func setListening(_ on: Bool) {
        mic.set(symbol: on ? "stop.fill" : "mic.fill", hot: on)
        setStatus(listening: on)
        setPlaceholder(on ? "Listening…" : idlePlaceholder)
        if !on { input.stringValue = "" }
    }
}
