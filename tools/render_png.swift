// Renders every frame of a character (PNG / HEIC / JPG / SVG) to PNG at a fixed height, for the Windows build.
//   swift tools/render_png.swift <src-character-dir> <dst-dir> [height=360]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: render_png.swift <src> <dst> [height]"); exit(1) }
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])
let height = CGFloat(Double(args.count > 3 ? args[3] : "360") ?? 360)
let fm = FileManager.default
var count = 0
for case let file as URL in fm.enumerator(at: src, includingPropertiesForKeys: nil)!
where ["png", "heic", "jpg", "jpeg", "svg"].contains(file.pathExtension.lowercased()) {
    guard let img = NSImage(contentsOf: file), img.size.height > 0 else { print("✗ \(file.lastPathComponent)"); continue }
    let rep0 = img.representations.first
    let srcH = CGFloat(rep0?.pixelsHigh ?? 0) > 0 ? CGFloat(rep0!.pixelsHigh) : img.size.height
    let h = file.pathExtension.lowercased() == "svg" ? height : min(height, srcH)
    let w = (img.size.width / img.size.height * h).rounded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    let rel = file.path.replacingOccurrences(of: src.path + "/", with: "")
    let out = dst.appendingPathComponent(rel).deletingPathExtension().appendingPathExtension("png")
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try rep.representation(using: .png, properties: [:])!.write(to: out)
    count += 1
}
print("rendered \(count) frames -> \(dst.path)")
