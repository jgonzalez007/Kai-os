//
//  KaiFileReader.swift
//  Kai Knowledge
//
//  Turns a file into plain text so Kai can search it: text and Markdown, CSV and JSON, web pages, Word and
//  RTF documents, PDFs, and images or scanned pages (read on this Mac with Apple's text recognition, so a
//  picture never leaves the computer). It only reads. It never opens a link inside a file or runs anything.
//

import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

public enum KaiFileReader {
    public static let plainExtensions: Set<String> = [
        "md", "markdown", "txt", "text", "csv", "tsv", "json", "yaml", "yml", "log", "toml", "ini", "tex",
        "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "java", "kt", "rb", "sh", "sql", "c", "h", "cpp", "cs", "php",
    ]
    public static let markupExtensions: Set<String> = ["html", "htm", "xml"]
    public static let documentExtensions: Set<String> = ["rtf", "doc", "docx", "odt"]
    public static let pdfExtensions: Set<String> = ["pdf"]
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    public static var supportedExtensions: Set<String> {
        plainExtensions.union(markupExtensions).union(documentExtensions).union(pdfExtensions).union(imageExtensions)
    }

    public static func supports(_ fileExtension: String) -> Bool { supportedExtensions.contains(fileExtension.lowercased()) }

    /// The biggest file Kai will open, by kind. Anything larger is skipped, never half-read.
    public static func maxBytes(for fileExtension: String) -> Int {
        let ext = fileExtension.lowercased()
        if plainExtensions.contains(ext) || markupExtensions.contains(ext) { return 2_000_000 }
        if imageExtensions.contains(ext) { return 20_000_000 }
        return 40_000_000
    }

    /// Pages of a scanned PDF that are read with text recognition.
    public static let maxScannedPages = 8
    /// A picture with less text than this is a photo, not a document.
    public static let minimumImageText = 25

    /// The text of the file, cut to `maxCharacters`, or nil when it can't be read or has no text.
    public static func read(_ url: URL, maxCharacters: Int = 60_000) -> String? {
        let ext = url.pathExtension.lowercased()
        let text: String?
        if plainExtensions.contains(ext) {
            text = plain(url)
        } else if markupExtensions.contains(ext) {
            text = plain(url).map(stripMarkup)
        } else if documentExtensions.contains(ext) {
            text = document(url, ext)
        } else if pdfExtensions.contains(ext) {
            text = pdf(url)
        } else if imageExtensions.contains(ext) {
            text = image(url)
        } else {
            text = nil
        }
        guard let text else { return nil }
        let cleaned = normalized(text)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(maxCharacters))
    }

    // MARK: Kinds

    private static func plain(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Web pages and XML without their tags, scripts and styles.
    static func stripMarkup(_ source: String) -> String {
        var text = source
        for block in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<!--[\\s\\S]*?-->"] {
            text = text.replacingOccurrences(of: block, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "</(p|div|li|h[1-6]|tr|br)>|<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text
    }

    private static func document(_ url: URL, _ ext: String) -> String? {
        let type: NSAttributedString.DocumentType
        switch ext {
        case "rtf": type = .rtf
        case "doc": type = .docFormat
        case "docx": type = .officeOpenXML
        default: type = .openDocument
        }
        guard let attributed = try? NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil) else { return nil }
        return attributed.string
    }

    private static func pdf(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url), !document.isLocked else { return nil }
        let text = document.string ?? ""
        // A scanned PDF has no text of its own: the first pages are read as pictures.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= max(60, document.pageCount * 10) { return text }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, maxScannedPages) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1700 / max(bounds.width, bounds.height, 1)
            let picture = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let cgImage = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) { pages.append(recognize(cgImage)) }
        }
        let scanned = pages.joined(separator: "\n\n")
        return scanned.count > text.count ? scanned : text
    }

    private static func image(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2600,
        ]
        guard let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let text = recognize(picture)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumImageText ? text : nil
    }

    private static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return "" }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Windows and old Mac line endings become new lines, runs of blank lines become one, and control
    /// characters (which a file can hold and a database should not) are dropped.
    static func normalized(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let kept = unified.unicodeScalars.filter { $0 == "\n" || $0 == "\t" || !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(kept))
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
