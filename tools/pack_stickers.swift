// Packs a character for shipping: every PNG -> HEIC (alpha kept) at a fixed height, ~10x smaller.
//   swift tools/pack_stickers.swift <src-character-dir> <dst-character-dir> [height=420]
import CoreImage
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: pack_stickers.swift <src> <dst> [height]"); exit(1) }
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])
let height = CGFloat(Double(args.count > 3 ? args[3] : "420") ?? 420)
let ctx = CIContext()
let fm = FileManager.default
let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
var count = 0

// vector characters (SVG) ship as they are
for case let file as URL in fm.enumerator(at: src, includingPropertiesForKeys: nil)! where file.pathExtension.lowercased() == "svg" {
    let out = dst.appendingPathComponent(file.path.replacingOccurrences(of: src.path + "/", with: ""))
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? fm.copyItem(at: file, to: out)
    count += 1
}

let items = fm.enumerator(at: src, includingPropertiesForKeys: nil)!
for case let file as URL in items where ["png", "heic", "jpg", "jpeg"].contains(file.pathExtension.lowercased()) {
    let rel = file.path.replacingOccurrences(of: src.path + "/", with: "")
    let out = dst.appendingPathComponent(rel).deletingPathExtension().appendingPathExtension("heic")
    try? fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let img = CIImage(contentsOf: file) else { print("✗ \(rel)"); continue }
    let s = min(1, height / img.extent.height)
    let scaled = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
    try ctx.writeHEIFRepresentation(of: scaled, to: out, format: .RGBA8,
                                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [quality: 0.75])
    count += 1
}
print("packed \(count) frames -> \(dst.path)")
