// Removes the background from character images using macOS Vision (no API, no credits).
//
//   swift tools/cutout.swift <out-dir> <image>...              each image cut out and trimmed on its own
//   swift tools/cutout.swift --sequence <out-dir> <image>...   animation frames: one shared crop so the
//                                                              character doesn't jitter between frames
//   swift tools/cutout.swift --track <out-dir> <image>...      frames where the character moves across the shot:
//                                                              each frame re-centred, feet on one baseline, one scale
//
// Output: transparent PNGs, scaled to 600px tall, with the same file names.
import AppKit
import CoreImage
import Vision

var args = Array(CommandLine.arguments.dropFirst())
let sequence = args.first == "--sequence"
let track = args.first == "--track"
if sequence || track { args.removeFirst() }
guard args.count >= 2 else {
    print("usage: cutout.swift [--sequence] <out-dir> <image>...")
    exit(1)
}
let outDir = URL(fileURLWithPath: args.removeFirst())
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let ctx = CIContext()
let targetHeight: CGFloat = 600

func cutout(_ url: URL) -> CIImage? {
    guard let src = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
        print("✗ can't read \(url.lastPathComponent)"); return nil
    }
    let handler = VNImageRequestHandler(ciImage: src)
    let req = VNGenerateForegroundInstanceMaskRequest()
    do {
        try handler.perform([req])
        guard let obs = req.results?.first else { print("✗ no subject found in \(url.lastPathComponent)"); return nil }
        let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
        return CIImage(cvPixelBuffer: buf)
    } catch {
        print("✗ \(url.lastPathComponent): \(error.localizedDescription)"); return nil
    }
}

/// Bounding box of pixels that aren't (nearly) transparent.
func opaqueBounds(_ img: CIImage) -> CGRect {
    guard let cg = ctx.createCGImage(img, from: img.extent) else { return img.extent }
    let w = cg.width, h = cg.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let bm = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img.extent }
    bm.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 20 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    if maxX < 0 { return img.extent }
    // bitmap rows run top-down; CIImage coordinates run bottom-up
    return CGRect(x: img.extent.minX + CGFloat(minX), y: img.extent.minY + CGFloat(h - 1 - maxY),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
}

func save(_ img: CIImage, crop: CGRect, name: String, canvas: CGSize? = nil) {
    let pad: CGFloat = 8
    var box = crop.insetBy(dx: -pad, dy: -pad)
    if let canvas {  // fixed-size box: feet on the bottom edge, centred horizontally
        box = CGRect(x: crop.midX - canvas.width / 2 - pad, y: crop.minY - pad,
                     width: canvas.width + pad * 2, height: canvas.height + pad * 2)
    }
    let scale = targetHeight / box.height
    let out = img.cropped(to: box)
        .transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let dest = outDir.appendingPathComponent((name as NSString).deletingPathExtension + ".png")
    do {
        try ctx.writePNGRepresentation(of: out, to: dest, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        print("✓ \(dest.lastPathComponent)")
    } catch { print("✗ write \(dest.lastPathComponent): \(error)") }
}

let inputs = args.map { URL(fileURLWithPath: $0) }
if track {
    let cut = inputs.compactMap { u in cutout(u).map { (u, $0, opaqueBounds($0)) } }
    let canvas = CGSize(width: cut.map { $0.2.width }.max() ?? 0, height: cut.map { $0.2.height }.max() ?? 0)
    for (u, img, b) in cut { save(img, crop: b, name: u.lastPathComponent, canvas: canvas) }
} else if sequence {
    let cut = inputs.compactMap { u in cutout(u).map { (u, $0) } }
    let union = cut.map { opaqueBounds($0.1) }.reduce(CGRect.null) { $0.union($1) }
    for (u, img) in cut { save(img, crop: union, name: u.lastPathComponent) }
} else {
    for u in inputs { if let img = cutout(u) { save(img, crop: opaqueBounds(img), name: u.lastPathComponent) } }
}
