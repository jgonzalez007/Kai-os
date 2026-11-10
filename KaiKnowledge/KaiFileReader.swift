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
    /// Excel workbooks and PowerPoint decks: zip files of XML, read for their text and cell values.
    public static let officeExtensions: Set<String> = ["xlsx", "pptx"]

    public static var supportedExtensions: Set<String> {
        plainExtensions.union(markupExtensions).union(documentExtensions).union(pdfExtensions).union(imageExtensions).union(officeExtensions)
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
        } else if ext == "xlsx" {
            text = KaiOfficeReader.workbook(url)
        } else if ext == "pptx" {
            text = KaiOfficeReader.slides(url)
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


/// Excel and PowerPoint files are zip archives of XML. They are opened with the system's unzip, one entry at a time and
/// with a size limit, never extracted to disk, and only their text is kept.
enum KaiOfficeReader {
    static func entries(_ url: URL) -> [String] {
        guard let data = run(["-Z1", url.path]) else { return [] }
        return String(decoding: data, as: UTF8.self).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func entry(_ url: URL, _ name: String) -> Data? { run(["-p", url.path, name]) }

    private static func run(_ arguments: [String], limit: Int = 12_000_000) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > limit { process.terminate(); return nil }
        }
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Part names in natural order: slide2 before slide10.
    static func numbered(_ names: [String], prefix: String) -> [String] {
        names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".xml") }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    static func workbook(_ url: URL) -> String? {
        let names = entries(url)
        let strings = entry(url, "xl/sharedStrings.xml").map { parseStrings($0) } ?? []
        var sheets: [String] = []
        for (index, name) in numbered(names, prefix: "xl/worksheets/sheet").prefix(4).enumerated() {
            guard let data = entry(url, name) else { continue }
            let rows = parseSheet(data, strings: strings)
            if !rows.isEmpty { sheets.append("Sheet \(index + 1)\n" + rows.joined(separator: "\n")) }
        }
        return sheets.isEmpty ? nil : sheets.joined(separator: "\n\n")
    }

    static func slides(_ url: URL) -> String? {
        let names = numbered(entries(url), prefix: "ppt/slides/slide")
        var out: [String] = []
        for (index, name) in names.enumerated() {
            guard let data = entry(url, name) else { continue }
            let collector = TextCollector(tag: "a:t", paragraph: "a:p")
            let parser = XMLParser(data: data); parser.delegate = collector; parser.parse()
            let text = collector.lines.joined(separator: "\n")
            if !text.isEmpty { out.append("Slide \(index + 1)\n" + text) }
        }
        return out.isEmpty ? nil : out.joined(separator: "\n\n")
    }

    static func parseStrings(_ data: Data) -> [String] {
        let collector = SharedStrings()
        let parser = XMLParser(data: data); parser.delegate = collector; parser.parse()
        return collector.items
    }

    static func parseSheet(_ data: Data, strings: [String], maxRows: Int = 4_000) -> [String] {
        let reader = SheetReader(strings: strings, maxRows: maxRows)
        let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return reader.rows
    }

    private final class TextCollector: NSObject, XMLParserDelegate {
        let tag: String, paragraph: String
        var lines: [String] = []
        private var current = ""
        private var inText = false
        init(tag: String, paragraph: String) { self.tag = tag; self.paragraph = paragraph }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) { if name == tag { inText = true } }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == tag { inText = false }
            if name == paragraph { let t = current.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { lines.append(t) }; current = "" }
        }
    }

    private final class SharedStrings: NSObject, XMLParserDelegate {
        var items: [String] = []
        private var current = ""
        private var inText = false
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "si" { current = "" }
            if name == "t" { inText = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "t" { inText = false }
            if name == "si" { items.append(current) }
        }
    }

    private final class SheetReader: NSObject, XMLParserDelegate {
        let strings: [String], maxRows: Int
        var rows: [String] = []
        private var cells: [String] = []
        private var type = ""
        private var value = ""
        private var inValue = false
        init(strings: [String], maxRows: Int) { self.strings = strings; self.maxRows = maxRows }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "row": cells = []
            case "c": type = attributes["t"] ?? ""; value = ""
            case "v", "t": inValue = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { value += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": inValue = false
            case "c":
                if type == "s", let index = Int(value.trimmingCharacters(in: .whitespaces)), index >= 0, index < strings.count { cells.append(strings[index]) }
                else { cells.append(value) }
            case "row":
                let line = cells.joined(separator: "\t").trimmingCharacters(in: .whitespaces)
                if !line.isEmpty, rows.count < maxRows { rows.append(line) }
            default: break
            }
        }
    }
}
