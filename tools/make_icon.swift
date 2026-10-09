// Builds an app icon (.icns) from a character image: denim tile with the face in a gold ring.
//   swift tools/make_icon.swift <character-image> <out.icns>
import AppKit
import Vision

let args = CommandLine.arguments
let img = NSImage(contentsOfFile: args[1])!
let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = CGFloat(cg.width), H = CGFloat(cg.height)
let req = VNDetectFaceRectanglesRequest()
try? VNImageRequestHandler(cgImage: cg).perform([req])
var crop = CGRect(x: W * 0.2, y: H * 0.7, width: W * 0.6, height: W * 0.6)
if let f = req.results?.first?.boundingBox {
    let r = CGRect(x: f.minX * W, y: f.minY * H, width: f.width * W, height: f.height * H)
    let side = max(r.width, r.height) * 1.9
    crop = CGRect(x: r.midX - side / 2, y: r.midY - side / 2 - r.height * 0.05, width: side, height: side)
        .intersection(CGRect(x: 0, y: 0, width: W, height: H))
}
let sx = img.size.width / W, sy = img.size.height / H
let src = CGRect(x: crop.minX * sx, y: crop.minY * sy, width: crop.width * sx, height: crop.height * sy)

func icon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let tile = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let rr = NSBezierPath(roundedRect: tile, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.64, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.31, alpha: 1)])!.draw(in: rr, angle: -90)
    let stitch = NSBezierPath(roundedRect: tile.insetBy(dx: s * 0.035, dy: s * 0.035), xRadius: s * 0.17, yRadius: s * 0.17)
    stitch.lineWidth = max(1, s * 0.012)
    stitch.setLineDash([s * 0.03, s * 0.02], count: 2, phase: 0)
    NSColor(calibratedRed: 0.91, green: 0.69, blue: 0.29, alpha: 1).setStroke()
    stitch.stroke()
    let face = NSRect(x: s * 0.18, y: s * 0.18, width: s * 0.64, height: s * 0.64)
    NSColor(calibratedRed: 0.91, green: 0.69, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(ovalIn: face.insetBy(dx: -s * 0.025, dy: -s * 0.025)).fill()
    NSColor(calibratedRed: 0.97, green: 0.91, blue: 0.79, alpha: 1).setFill()
    NSBezierPath(ovalIn: face).fill()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: face).addClip()
    img.draw(in: face, from: src, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Bro.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! icon(px).write(to: set.appendingPathComponent("icon_\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", args[2]]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "icon -> \(args[2])" : "iconutil failed")
