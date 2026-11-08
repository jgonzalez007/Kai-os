//
//  KaiUpdates.swift
//  Kai Shared
//
//  Tells the person when a newer Kai OS exists. It only reads the public GitHub release list and
//  opens the release page: it never downloads or installs anything by itself.
//

import Foundation

public struct KaiVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// "v1.2.3", "1.2", "1.2.3-beta" all parse. Anything without a leading number does not.
    public init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let core = s.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let numbers = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: KaiVersion, rhs: KaiVersion) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: KaiVersion, rhs: KaiVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

public struct KaiAvailableUpdate: Equatable, Sendable {
    public let version: KaiVersion
    public let pageURL: URL
    public let notes: String
}

public enum KaiUpdates {
    public static let releasesAPI = URL(string: "https://api.github.com/repos/jgonzalez007/Kai-os/releases/latest")!
    public static let installCommand = "curl -fsSL https://raw.githubusercontent.com/jgonzalez007/Kai-os/main/scripts/install.sh | bash"
    /// At most one automatic check per day.
    public static let interval: TimeInterval = 24 * 3600

    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Reads GitHub's "latest release" JSON. Drafts and prereleases never count. The page must
    /// be on github.com, so a changed reply cannot send someone to another site.
    public static func parseLatest(_ data: Data, current: KaiVersion) -> KaiAvailableUpdate? {
        struct Release: Decodable {
            let tag_name: String
            let html_url: String
            let body: String?
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true,
              let version = KaiVersion(release.tag_name), version > current,
              let url = URL(string: release.html_url), url.scheme == "https", url.host == "github.com" else { return nil }
        let notes = String((release.body ?? "").prefix(600))
        return KaiAvailableUpdate(version: version, pageURL: url, notes: notes)
    }

    public static func check(current: KaiVersion,
                             fetch: (URL) async throws -> Data = { url in
                                 var request = URLRequest(url: url)
                                 request.timeoutInterval = 10
                                 request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                                 return try await URLSession.shared.data(for: request).0
                             }) async throws -> KaiAvailableUpdate? {
        parseLatest(try await fetch(releasesAPI), current: current)
    }
}
