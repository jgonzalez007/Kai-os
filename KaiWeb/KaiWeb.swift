//
//  KaiWeb.swift
//  Kai Web
//
//  Looking things up on the web for the assistant: a search, and reading one page. Everything that comes
//  back is untrusted text written by strangers, so it is cut down to plain text and handed to the model as
//  data. The rules that keep this safe are here and are tested:
//    - only http and https, no logins in the address, nothing on this Mac or the local network
//    - a page can only be opened if it came from a search result or the person typed the link
//    - no cookies, no stored data, a size limit and a time limit
//

import Foundation

public struct KaiWebResult: Equatable, Sendable {
    public let title: String
    public let url: URL
    public let snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public enum KaiWebError: LocalizedError, Equatable, Sendable {
    case invalidAddress
    case notAllowed
    case privateAddress
    case notReadable(String)
    case http(Int)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: return "That is not a web address I can open."
        case .notAllowed: return "I only open links that came from a web search or that you gave me."
        case .privateAddress: return "I don't open addresses on this Mac or on your local network."
        case .notReadable(let kind): return "That link is \(kind), not a web page I can read."
        case .http(let status): return "The site answered with an error (\(status))."
        case .network(let message): return "I couldn't reach the web: \(message)"
        }
    }
}

// MARK: - Addresses

public enum KaiWebURL {
    /// A web address I may open, or nil. Never a login in the address, never this Mac or a private network.
    public static func validate(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_000,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return isPrivate(host: host) ? nil : url
    }

    /// Hosts that are the machine itself, the local network, or an address written in a way that hides which.
    public static func isPrivate(host raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host.isEmpty || host == "localhost" { return true }
        for suffix in [".localhost", ".local", ".internal", ".lan", ".home", ".corp", ".intranet", ".home.arpa"] where host.hasSuffix(suffix) { return true }
        if host.contains(":") { return isPrivateIPv6(host) }
        // A host that is only digits, or a hex or octal number, is an IP address in disguise.
        if host.allSatisfy({ $0.isNumber }) || host.hasPrefix("0x") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4, parts.allSatisfy({ Int($0) != nil }) {
            let n = parts.compactMap { Int($0) }
            guard n.allSatisfy({ (0...255).contains($0) }) else { return true }
            return isPrivateIPv4(n[0], n[1])
        }
        if parts.contains(where: { $0.hasPrefix("0") && $0.count > 1 && Int($0) != nil }) { return true }
        return false
    }

    static func isPrivateIPv4(_ a: Int, _ b: Int) -> Bool {
        a == 0 || a == 10 || a == 127 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168) || (a == 100 && (64...127).contains(b)) || a >= 224
    }

    static func isPrivateIPv6(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "::" || h == "::1" { return true }
        if h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe8") || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb") { return true }
        // An IPv4 address carried inside an IPv6 one.
        if let tail = h.split(separator: ":").last, tail.contains("."), validate("http://\(tail)/") == nil { return true }
        return h.hasPrefix("::ffff:")
    }

    /// Web addresses written in a piece of text, such as a message from the person.
    public static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url }.compactMap { validate($0.absoluteString) }
    }
}

// MARK: - Reading search results and pages

public enum KaiWebSearchPage {
    /// Reads the results page of DuckDuckGo's plain HTML search. Redirect links are unwrapped to the real address.
    public static func parse(_ html: String, limit: Int = 6) -> [KaiWebResult] {
        var results: [KaiWebResult] = []
        let anchor = try? NSRegularExpression(pattern: #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let snippet = try? NSRegularExpression(pattern: #"class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</(?:a|td|div)>"#, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = html as NSString
        let all = NSRange(location: 0, length: ns.length)
        let anchors = anchor?.matches(in: html, range: all) ?? []
        let snippets = snippet?.matches(in: html, range: all) ?? []
        for (index, match) in anchors.enumerated() {
            guard let url = realURL(ns.substring(with: match.range(at: 1))) else { continue }
            let title = KaiWebText.plain(ns.substring(with: match.range(at: 2)))
            guard !title.isEmpty else { continue }
            // The snippet that follows this result, before the next one.
            let end = index + 1 < anchors.count ? anchors[index + 1].range.location : ns.length
            let text = snippets.first { $0.range.location > match.range.location && $0.range.location < end }
                .map { KaiWebText.plain(ns.substring(with: $0.range(at: 1))) } ?? ""
            results.append(KaiWebResult(title: title, url: url, snippet: String(text.prefix(300))))
            if results.count == limit { break }
        }
        return results
    }

    /// Unwraps //duckduckgo.com/l/?uddg=<address>, and drops ads and anything that is not a public web address.
    static func realURL(_ raw: String) -> URL? {
        var text = raw.replacingOccurrences(of: "&amp;", with: "&")
        if text.hasPrefix("//") { text = "https:" + text }
        guard let url = URL(string: text) else { return nil }
        if url.host?.hasSuffix("duckduckgo.com") == true {
            if url.path.hasPrefix("/y.js") { return nil }   // an ad
            guard let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "uddg" })?.value else { return nil }
            return KaiWebURL.validate(target)
        }
        return KaiWebURL.validate(text)
    }
}

public enum KaiWebText {
    /// A page as plain text: scripts, styles and tags removed, entities decoded, blank space tidied.
    public static func extract(fromHTML html: String, limit: Int = 12_000) -> String {
        var text = html
        for block in ["script", "style", "noscript", "svg", "head", "title", "nav", "footer", "form", "iframe"] {
            text = text.replacingOccurrences(of: "<\(block)\\b[^>]*>.*?</\(block)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<!--.*?-->", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</?(p|div|br|li|h[1-6]|tr|section|article|header)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let cleaned = plain(text, keepLines: true)
        return cleaned.count > limit ? String(cleaned.prefix(limit)) + "…" : cleaned
    }

    public static func title(ofHTML html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>.*?</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        let t = plain(String(html[range]))
        return t.isEmpty ? nil : String(t.prefix(150))
    }

    /// Strips tags, decodes entities and tidies the spaces.
    static func plain(_ html: String, keepLines: Bool = false) -> String {
        // Inline tags (bold, links) vanish without a gap, so "<b>actors</b>," stays "actors,".
        var text = html.replacingOccurrences(of: "</?(b|strong|em|i|u|span|a|mark|code|small|sup|sub)\\b[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = decode(text)
        let scalars = text.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" && keepLines { return "\n" }
            return CharacterSet.controlCharacters.contains(scalar) || scalar == "\u{00A0}" ? " " : Character(scalar)
        }
        let lines = String(scalars).components(separatedBy: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
        return lines.filter { !$0.isEmpty }.joined(separator: keepLines ? "\n" : " ")
    }

    static func decode(_ text: String) -> String {
        var out = text
        for (entity, value) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…")] {
            out = out.replacingOccurrences(of: entity, with: value)
        }
        // Numeric entities such as &#8217; and &#x2019;
        if let numeric = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]{1,6});") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for match in numeric.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                let hex = ns.substring(with: match.range(at: 1)) == "x"
                if let code = UInt32(ns.substring(with: match.range(at: 2)), radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result += String(Character(scalar))
                }
                last = match.range.location + match.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}

// MARK: - Network

public protocol KaiWebTransport: Sendable {
    /// Fetches one address. It must not send cookies, and must check every redirect with `KaiWebURL.validate`.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real network, with no cookies or cache, a size cap and redirects that are checked.
public final class KaiURLSessionTransport: NSObject, KaiWebTransport, URLSessionTaskDelegate, @unchecked Sendable {
    public static let maxBytes = 1_500_000
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public override init() { super.init() }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Check what the name really points at, so a public name cannot lead to a private address.
        if let host = request.url?.host, await Self.resolvesToPrivate(host) { throw KaiWebError.privateAddress }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw KaiWebError.network("no answer") }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= Self.maxBytes { break }
        }
        return (data, http)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url?.absoluteString, KaiWebURL.validate(target) != nil else { completionHandler(nil); return }
        completionHandler(request)
    }

    static func resolvesToPrivate(_ host: String) async -> Bool {
        await Task.detached {
            var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
            defer { freeaddrinfo(result) }
            var cursor: UnsafeMutablePointer<addrinfo>? = first
            while let info = cursor {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
                   KaiWebURL.isPrivate(host: String(cString: buffer)) { return true }
                cursor = info.pointee.ai_next
            }
            return false
        }.value
    }
}

// MARK: - The session

/// One conversation's web access. It remembers which addresses are fair to open: those from search results
/// and those the person wrote.
public final class KaiWebSession: @unchecked Sendable {
    public static let userAgent = "Mozilla/5.0 (Macintosh) KaiOS/1.1"

    private let transport: KaiWebTransport
    private let lock = NSLock()
    private var allowed = Set<String>()

    public init(transport: KaiWebTransport = KaiURLSessionTransport()) {
        self.transport = transport
    }

    private func key(_ url: URL) -> String { url.absoluteString.lowercased() }

    public func allow(_ url: URL) { lock.lock(); allowed.insert(key(url)); lock.unlock() }
    public func isAllowed(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return allowed.contains(key(url)) }

    /// Links in something the person wrote are fair to open.
    public func noteUserText(_ text: String) { KaiWebURL.links(in: text).forEach(allow) }

    public func search(_ query: String) async throws -> [KaiWebResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var request = URLRequest(url: URL(string: "https://html.duckduckgo.com/html/")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "q", value: String(q.prefix(300)))]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw KaiWebError.http(response.statusCode) }
        let results = KaiWebSearchPage.parse(String(decoding: data, as: UTF8.self))
        results.forEach { allow($0.url) }
        return results
    }

    /// The text of one page, with its title first.
    public func read(_ address: String) async throws -> (title: String?, text: String, url: URL) {
        guard let url = KaiWebURL.validate(address) else {
            throw (URL(string: address)?.host.map(KaiWebURL.isPrivate(host:)) == true) ? KaiWebError.privateAddress : KaiWebError.invalidAddress
        }
        guard isAllowed(url) else { throw KaiWebError.notAllowed }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,text/plain,application/json;q=0.9", forHTTPHeaderField: "Accept")
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else { throw KaiWebError.http(response.statusCode) }
        let type = (response.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let readable = type.isEmpty || type.hasPrefix("text/") || type.contains("json") || type.contains("xml")
        guard readable else { throw KaiWebError.notReadable(type.split(separator: ";").first.map(String.init) ?? "another kind of file") }
        let body = String(decoding: data, as: UTF8.self)
        if type.contains("html") || type.isEmpty {
            return (KaiWebText.title(ofHTML: body), KaiWebText.extract(fromHTML: body), url)
        }
        return (nil, String(body.prefix(12_000)), url)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.data(for: request) }
        catch let error as KaiWebError { throw error }
        catch { throw KaiWebError.network(error.localizedDescription) }
    }
}
