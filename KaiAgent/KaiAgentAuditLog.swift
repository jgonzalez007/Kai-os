import Foundation

/// A line-by-line record of everything the agent proposed, was refused, and did.
/// Screenshots are not saved. The file is readable only by the user.
public final class KaiAgentAuditLog: KaiAgentObserver, @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL = KaiAgentAuditLog.defaultURL()) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true)
            .appendingPathComponent("agent-log.jsonl")
    }

    public func event(_ event: KaiAgentEvent) {
        if case .activity = event { return }
        let (kind, detail) = Self.describe(event)
        append(["time": ISO8601DateFormatter().string(from: Date()), "event": kind, "detail": detail])
    }

    static func describe(_ event: KaiAgentEvent) -> (String, String) {
        switch event {
        case .started(let task, let mode): return ("started", "\(mode.rawValue): \(task)")
        case .thought(let step, let text): return ("thought", "step \(step): \(text)")
        case .proposed(let step, let summary): return ("proposed", "step \(step): \(summary)")
        case .blocked(let step, let summary, let reason): return ("blocked", "step \(step): \(summary) — \(reason)")
        case .declined(let step, let summary): return ("declined", "step \(step): \(summary)")
        case .approved(let step, let summary): return ("approved", "step \(step): \(summary)")
        case .performed(let step, let summary, _): return ("performed", "step \(step): \(summary)")
        case .finished(let outcome): return ("finished", outcome.summary)
        case .activity(_, let text): return ("activity", text)
        }
    }

    private func append(_ fields: [String: String]) {
        guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
