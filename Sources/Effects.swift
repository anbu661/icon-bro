import AppKit

/// Particle effects for Bro's vanish / appear: smoke poof, sparkle swoosh trail, arrival pop.
/// Drawn in a transparent, click-through window covering the screen, just below Bro.
final class EffectsLayer {
    private let window: NSPanel
    private let root = CALayer()
    private let origin: NSPoint
    private var trail: CAEmitterLayer?

    init(below panel: NSWindow) {
        let screen = panel.screen?.frame ?? NSScreen.main?.frame ?? .zero
        origin = screen.origin
        window = NSPanel(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = panel.level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.size))
        view.wantsLayer = true
        view.layer?.addSublayer(root)
        root.frame = view.bounds
        window.contentView = view
        window.order(.below, relativeTo: panel.windowNumber)
    }

    private func local(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x - origin.x, y: p.y - origin.y) }

    // MARK: particle images

    private static func dot(_ color: NSColor, soft: Bool, size: CGFloat = 32) -> CGImage? {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            if soft {
                NSGradient(colors: [color, color.withAlphaComponent(0)])?.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero)
            } else {
                color.setFill()
                NSBezierPath(ovalIn: r).fill()
            }
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func star(_ color: NSColor, size: CGFloat = 32) -> CGImage? {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let c = NSPoint(x: r.midX, y: r.midY)
            let p = NSBezierPath()
            for i in 0..<8 {
                let rad = i % 2 == 0 ? size / 2 : size / 7
                let a = CGFloat(i) * .pi / 4 + .pi / 2
                let pt = NSPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad)
                i == 0 ? p.move(to: pt) : p.line(to: pt)
            }
            p.close()
            color.setFill()
            p.fill()
            return true
        }
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static let smokeImg = dot(NSColor(white: 1, alpha: 0.9), soft: true, size: 64)
    static let sparkImg = star(NSColor(calibratedRed: 1, green: 0.84, blue: 0.35, alpha: 1))
    static let glintImg = dot(NSColor(calibratedRed: 0.7, green: 0.85, blue: 1, alpha: 1), soft: true)

    private func cell(_ image: CGImage?, birth: Float, life: Float, velocity: CGFloat, spread: CGFloat = .pi * 2,
                      scale: CGFloat, scaleSpeed: CGFloat, alphaSpeed: Float, spin: CGFloat = 0) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = image
        c.birthRate = birth
        c.lifetime = life
        c.lifetimeRange = life * 0.4
        c.velocity = velocity
        c.velocityRange = velocity * 0.5
        c.emissionRange = spread
        c.scale = scale
        c.scaleRange = scale * 0.4
        c.scaleSpeed = scaleSpeed
        c.alphaSpeed = alphaSpeed
        c.spin = spin
        c.spinRange = spin * 2
        return c
    }

    // MARK: effects

    /// Big smoke-and-sparkle burst ("poof").
    func poof(at p: NSPoint, size: CGFloat = 1) {
        let e = CAEmitterLayer()
        e.emitterPosition = local(p)
        e.emitterShape = .circle
        e.emitterSize = CGSize(width: 60 * size, height: 60 * size)
        e.renderMode = .additive
        e.emitterCells = [
            cell(Self.smokeImg, birth: 260, life: 0.8, velocity: 140 * size, scale: 0.7 * size, scaleSpeed: 0.9, alphaSpeed: -1.3),
            cell(Self.sparkImg, birth: 160, life: 0.9, velocity: 260 * size, scale: 0.5 * size, scaleSpeed: -0.3, alphaSpeed: -1.1, spin: 4),
            cell(Self.glintImg, birth: 120, life: 0.6, velocity: 200 * size, scale: 0.35 * size, scaleSpeed: -0.2, alphaSpeed: -1.6),
        ]
        root.addSublayer(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { e.birthRate = 0 }     // one burst, then let it fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { e.removeFromSuperlayer() }
    }

    /// Starts a sparkle trail; move it with `trail(to:)`.
    func startTrail(at p: NSPoint) {
        let e = CAEmitterLayer()
        e.emitterPosition = local(p)
        e.emitterShape = .point
        e.renderMode = .additive
        e.emitterCells = [
            cell(Self.sparkImg, birth: 140, life: 0.55, velocity: 40, scale: 0.35, scaleSpeed: -0.5, alphaSpeed: -1.8, spin: 3),
            cell(Self.smokeImg, birth: 70, life: 0.45, velocity: 20, scale: 0.4, scaleSpeed: -0.3, alphaSpeed: -2.0),
            cell(Self.glintImg, birth: 90, life: 0.4, velocity: 30, scale: 0.25, scaleSpeed: -0.4, alphaSpeed: -2.2),
        ]
        root.addSublayer(e)
        trail = e
    }

    func trail(to p: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trail?.emitterPosition = local(p)
        CATransaction.commit()
    }

    func stopTrail() { trail?.birthRate = 0 }

    /// Clean up once the particles have faded.
    func finish(after seconds: Double = 1.2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [window] in window.orderOut(nil) }
    }
}
