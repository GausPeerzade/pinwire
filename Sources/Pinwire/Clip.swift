import AppKit
import UniformTypeIdentifiers

/// Something you copied: every representation of every pasteboard item,
/// kept as a small file in Pinwire's folder so it hangs on the line like a
/// screenshot, survives a relaunch, and can be put back on the clipboard
/// exactly as it was.
struct Clip {
    /// One dictionary per pasteboard item, from type identifier to bytes.
    var items: [[String: Data]]
    /// The app that was in front when it was copied.
    var source: String?

    static let fileExtension = "tclip"

    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pinwire/Clips", isDirectory: true)
    }()

    /// A single representation bigger than this is left out, and a clip
    /// bigger than the total is not kept at all. Huge copies (a whole video,
    /// a raw TIFF of a 6K display) are not worth holding in memory or on disk.
    static let maxTypeBytes = 16 * 1024 * 1024
    static let maxTotalBytes = 32 * 1024 * 1024

    // MARK: Capturing and restoring

    /// Reads every representation on the pasteboard. Returns nil when there
    /// is nothing worth keeping.
    /// The whole read must happen within one pasteboard generation: if
    /// another copy lands meanwhile, the half-read clip is thrown away and
    /// the next check picks up the new one.
    static func capture(from pasteboard: NSPasteboard, source: String?,
                        skipping skipTypes: Set<String> = []) -> Clip? {
        let generation = pasteboard.changeCount
        var total = 0
        var items: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let types = item.types.map(\.rawValue)
            // Any item marked private makes the whole copy private.
            guard Set(types).isDisjoint(with: skipTypes) else { return nil }
            // A copied file only needs its URL and name: the icon images
            // Finder adds are redrawn from the file anyway.
            let isFile = types.contains(NSPasteboard.PasteboardType.fileURL.rawValue)
            let tiff = NSPasteboard.PasteboardType.tiff.rawValue
            var reps: [String: Data] = [:]
            for type in types where type != tiff && !(isFile && type == "com.apple.icns") {
                guard let data = item.data(forType: .init(type)), data.count <= maxTypeBytes else { continue }
                total += data.count
                guard total <= maxTotalBytes else { return nil }
                reps[type] = data
            }
            // A TIFF is the same picture as a PNG, often ten times bigger:
            // it is only kept when no usable PNG was.
            if types.contains(tiff), !isFile, reps[NSPasteboard.PasteboardType.png.rawValue] == nil,
               let data = item.data(forType: .tiff), data.count <= maxTypeBytes {
                total += data.count
                guard total <= maxTotalBytes else { return nil }
                reps[tiff] = data
            }
            if !reps.isEmpty { items.append(reps) }
        }
        guard pasteboard.changeCount == generation else { return nil }
        return items.isEmpty ? nil : Clip(items: items, source: source)
    }

    /// Puts the clip back on the pasteboard with every original
    /// representation, marked as Pinwire's own so it is not hung again.
    func write(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems())
    }

    func pasteboardItems() -> [NSPasteboardItem] {
        items.enumerated().map { index, reps in
            let entry = NSPasteboardItem()
            for (type, data) in reps { entry.setData(data, forType: .init(type)) }
            if index == 0 { entry.setData(Data(), forType: ClipboardWatcher.ownType) }
            return entry
        }
    }

    /// Same content, wherever and whenever it was copied.
    var signature: Int {
        var hasher = Hasher()
        for reps in items {
            for type in reps.keys.sorted() {
                hasher.combine(type)
                hasher.combine(reps[type])
            }
        }
        return hasher.finalize()
    }

    // MARK: Saving

    func save() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        // Also tightens a folder made by an earlier version.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.folder.path)
        let url = Self.folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.fileExtension)
        var plist: [String: Any] = ["items": items]
        if let source { plist["source"] = source }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        // Readable by you alone: what you copy is nobody else's business.
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    static func load(_ url: URL) -> Clip? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let items = plist["items"] as? [[String: Data]], !items.isEmpty else { return nil }
        return Clip(items: items, source: plist["source"] as? String)
    }

    static func isClip(_ url: URL) -> Bool { url.pathExtension == fileExtension }

    // MARK: What it is

    private func data(_ type: NSPasteboard.PasteboardType) -> Data? {
        items.lazy.compactMap { $0[type.rawValue] }.first
    }

    var fileURLs: [URL] {
        items.compactMap { reps in
            reps[NSPasteboard.PasteboardType.fileURL.rawValue]
                .flatMap { String(data: $0, encoding: .utf8) }
                .flatMap { URL(string: $0) }
        }
    }

    var text: String? {
        if let data = data(.string), let s = String(data: data, encoding: .utf8) { return s }
        if let data = data(.rtf),
           let s = NSAttributedString(rtf: data, documentAttributes: nil)?.string { return s }
        return nil
    }

    /// A copied link, or text that is nothing but one.
    var link: URL? {
        if let data = data(.URL), let s = String(data: data, encoding: .utf8), let url = URL(string: s),
           url.scheme != nil, !url.isFileURL { return url }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
    }

    private var imageData: Data? {
        for reps in items {
            for (type, data) in reps where UTType(type)?.conforms(to: .image) == true { return data }
        }
        return nil
    }

    private var color: NSColor? {
        data(.color).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: $0) }
    }

    /// A short description for VoiceOver.
    var accessibilityText: String {
        let files = fileURLs
        if !files.isEmpty { return L("Copied file ", "Archivo copiado ") + files.map(\.lastPathComponent).joined(separator: ", ") }
        if let link { return L("Copied link ", "Enlace copiado ") + link.absoluteString }
        if let text { return L("Copied text: ", "Texto copiado: ") + String(text.prefix(120)) }
        return L("Copied item", "Elemento copiado")
    }

    /// Whether double click has something to open.
    var canOpen: Bool { !fileURLs.isEmpty || link != nil }

    func open() {
        let files = fileURLs
        if !files.isEmpty {
            files.forEach { NSWorkspace.shared.open($0) }
        } else if let link {
            NSWorkspace.shared.open(link)
        }
    }

    // MARK: The card on the line

    /// The card a clip hangs as. Files, pictures, links and text each get
    /// their own look; the rest show what kind of data they are.
    func thumbnail() -> NSImage {
        let files = fileURLs
        if !files.isEmpty { return Card.file(files) }
        if let imageData, let image = imageThumbnail(imageData) { return image }
        if let color { return Card.color(color) }
        if let link { return Card.text(link.absoluteString, symbol: "link", source: source) }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Card.text(text, symbol: "text.alignleft", source: source)
        }
        let kind = items.first?.keys.sorted().first.flatMap { UTType($0)?.localizedDescription }
        return Card.text(kind ?? L("Copied item", "Elemento copiado"), symbol: "doc.on.clipboard", source: source)
    }

    private func imageThumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Paper cards drawn for clips that are not pictures. They are drawn on
/// demand at the screen's resolution, and look the same in light and dark
/// mode, like a note pegged to the line.
private enum Card {
    static let size = NSSize(width: 136, height: 96)
    private static let paper = NSColor(white: 0.985, alpha: 1)
    private static let ink = NSColor(white: 0.13, alpha: 1)
    private static let faint = NSColor(white: 0.45, alpha: 1)
    private static let padding: CGFloat = 9

    static func text(_ string: String, symbol: String, source: String?) -> NSImage {
        let body = String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        return draw { rect in
            let footer: CGFloat = 14
            drawFooter(in: rect, symbol: symbol, source: source)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: ink,
                .paragraphStyle: style,
            ]
            let textRect = NSRect(x: padding, y: padding, width: rect.width - padding * 2,
                                  height: rect.height - padding * 2 - footer)
            (body as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: attrs, context: nil)
        }
    }

    static func file(_ urls: [URL]) -> NSImage {
        draw { rect in
            let icon = NSWorkspace.shared.icon(forFile: urls[0].path)
            let side: CGFloat = 46
            icon.draw(in: NSRect(x: (rect.width - side) / 2, y: 10, width: side, height: side))
            var name = urls[0].lastPathComponent
            if urls.count > 1 { name += L(" and \(urls.count - 1) more", " y \(urls.count - 1) más") }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingMiddle
            (name as NSString).draw(
                in: NSRect(x: padding, y: 62, width: rect.width - padding * 2, height: 16),
                withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                 .foregroundColor: ink, .paragraphStyle: style])
        }
    }

    static func color(_ color: NSColor) -> NSImage {
        draw { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: padding, dy: padding).offsetBy(dx: 0, dy: -7)
                .insetBy(dx: 0, dy: 7), xRadius: 6, yRadius: 6).fill()
            let hex = color.usingColorSpace(.sRGB).map {
                String(format: "#%02X%02X%02X", Int($0.redComponent * 255),
                       Int($0.greenComponent * 255), Int($0.blueComponent * 255))
            } ?? ""
            (hex as NSString).draw(at: NSPoint(x: padding, y: rect.height - padding - 12),
                                   withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium),
                                                    .foregroundColor: faint])
        }
    }

    private static func drawFooter(in rect: NSRect, symbol: String, source: String?) {
        let y = rect.height - padding - 10
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8.5, weight: .semibold)) {
            let tinted = NSImage(size: image.size, flipped: false) { r in
                image.draw(in: r)
                faint.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: padding, y: y, width: image.size.width, height: image.size.height))
        }
        if let source {
            (source as NSString).draw(
                in: NSRect(x: padding + 14, y: y - 1.5, width: rect.width - padding * 2 - 14, height: 12),
                withAttributes: [.font: NSFont.systemFont(ofSize: 8.5, weight: .medium), .foregroundColor: faint])
        }
    }

    /// Draws in a flipped context, so y grows downwards like the layout.
    private static func draw(_ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            paper.setFill()
            rect.fill()
            body(rect)
            return true
        }
    }
}
