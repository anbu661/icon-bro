import Foundation

/// Sorts the loose files at the top of a folder into Images/, Videos/, Audio/, Documents/ and Archives/.
/// Sub-folders and unknown file types are left alone. Every run is logged so it can be undone.
struct TidyPlan {
    let folder: URL
    var moves: [(from: URL, to: URL)] = []
    var counts: [String: Int] = [:]

    var summary: String {
        let nouns = ["Images": "image", "Videos": "video", "Audio": "audio file", "Documents": "document", "Archives": "archive"]
        return Tidy.categories.compactMap { name, _ in
            counts[name].map { "\($0) \(nouns[name] ?? name)\($0 == 1 ? "" : "s")" }
        }.joined(separator: ", ")
    }
}

enum Tidy {
    static let categories: [(String, Set<String>)] = [
        ("Images", ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "svg", "bmp", "tif", "tiff", "avif"]),
        ("Videos", ["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv"]),
        ("Audio", ["mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"]),
        ("Documents", ["pdf", "doc", "docx", "txt", "md", "rtf", "pages", "ppt", "pptx", "key", "xls", "xlsx", "csv", "numbers"]),
        ("Archives", ["zip", "rar", "7z", "tar", "gz", "tgz", "dmg", "pkg"]),
    ]
    static let inProgress: Set<String> = ["crdownload", "download", "part", "partial"]
    static var logDir: URL { supportDir.appendingPathComponent("tidy-log") }

    /// "downloads", "my Desktop folder", "~/Projects/foo" → a folder URL that exists.
    static func resolve(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("~") { n = home.path + n.dropFirst() }
        var url: URL
        if n.hasPrefix("/") {
            url = URL(fileURLWithPath: n)
        } else {
            let key = n.lowercased().replacingOccurrences(of: "my ", with: "")
                .replacingOccurrences(of: " folder", with: "").trimmingCharacters(in: .whitespaces)
            let known = ["downloads": "Downloads", "download": "Downloads", "desktop": "Desktop",
                         "documents": "Documents", "pictures": "Pictures", "movies": "Movies", "music": "Music"]
            url = home.appendingPathComponent(known[key] ?? n)
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    static func plan(_ folder: URL) throws -> TidyPlan {
        let fm = FileManager.default
        var plan = TidyPlan(folder: folder)
        var taken = Set<String>()
        let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                               options: [.skipsHiddenFiles])
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true && values?.isPackage != true { continue }
            let ext = item.pathExtension.lowercased()
            if inProgress.contains(ext) { continue }
            guard let (category, _) = categories.first(where: { $0.1.contains(ext) }) else { continue }
            let destDir = folder.appendingPathComponent(category)
            var dest = destDir.appendingPathComponent(item.lastPathComponent)
            var n = 1
            while fm.fileExists(atPath: dest.path) || taken.contains(dest.path) {
                let base = item.deletingPathExtension().lastPathComponent
                dest = destDir.appendingPathComponent("\(base) (\(n)).\(item.pathExtension)")
                n += 1
            }
            taken.insert(dest.path)
            plan.moves.append((item, dest))
            plan.counts[category, default: 0] += 1
        }
        return plan
    }

    /// Returns (moved, failed).
    static func apply(_ plan: TidyPlan) -> (Int, Int) {
        let fm = FileManager.default
        var done: [[String]] = []
        var failed = 0
        for (from, to) in plan.moves {
            do {
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
                done.append([from.path, to.path])
            } catch { failed += 1 }
        }
        if !done.isEmpty {
            try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            if let data = try? JSONSerialization.data(withJSONObject: done, options: .prettyPrinted) {
                try? data.write(to: logDir.appendingPathComponent("\(stamp).json"))
            }
        }
        return (done.count, failed)
    }

    /// Moves everything from the most recent tidy back where it was. Returns how many files went back.
    static func undoLast() -> Int? {
        let fm = FileManager.default
        guard let latest = (try? fm.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil))?
                .filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last,
              let data = try? Data(contentsOf: latest),
              let moves = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return nil }
        var restored = 0
        for m in moves where m.count == 2 && !fm.fileExists(atPath: m[0]) {
            if (try? fm.moveItem(atPath: m[1], toPath: m[0])) != nil { restored += 1 }
        }
        // remove category folders the tidy created if they're now empty
        for dir in Set(moves.compactMap { $0.count == 2 ? URL(fileURLWithPath: $0[1]).deletingLastPathComponent() : nil })
        where ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["x"]).filter({ !$0.hasPrefix(".") }).isEmpty {
            try? fm.removeItem(at: dir)
        }
        try? fm.removeItem(at: latest)
        return restored
    }
}
