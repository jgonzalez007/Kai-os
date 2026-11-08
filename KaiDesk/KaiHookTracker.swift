//
//  KaiHookTracker.swift
//  Kai Desk
//
//  Follows Claude Code from its hook events: when a turn started, which helper agents ("clones")
//  are running, and when something finished. Pure state, no timers: callers pass the time.
//

import Foundation

public struct KaiHookClone: Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let label: String
    public let project: String
    public var started: Date
    public var lastSeen: Date
    public var waitingForYou: Bool
}

public struct KaiHookDone: Equatable, Sendable {
    public let project: String
    /// Nil when the start of the turn was not seen.
    public let duration: TimeInterval?
    public let failed: Bool

    public var text: String {
        var parts = [failed ? "Stopped with an error" : "Done", project]
        if let duration { parts.append(KaiHookDone.format(duration)) }
        return parts.joined(separator: " · ")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m \(total % 60)s"
    }
}

public struct KaiHookTracker: Equatable, Sendable {
    /// A clone with no news for this long is dropped, in case its stop event was missed.
    public static let cloneLifetime: TimeInterval = 20 * 60

    public private(set) var clones: [KaiHookClone] = []
    private var turnStarts: [String: Date] = [:]

    public init() {}

    public static func label(forAgentType type: String?) -> String {
        switch type {
        case "Explore": return "Explore"
        case "Plan": return "Plan"
        case .some(let name) where !name.isEmpty && name != "general-purpose": return name
        default: return "Helper"
        }
    }

    /// Applies an event. Returns something to announce, if any.
    @discardableResult
    public mutating func apply(_ event: KaiHookEvent, now: Date = Date()) -> KaiHookDone? {
        switch event.name {
        case .userPromptSubmit:
            turnStarts[event.sessionID] = now
            return nil
        case .subagentStart:
            guard let id = event.agentID, !id.isEmpty else { return nil }
            clones.removeAll { $0.id == id }
            clones.append(KaiHookClone(
                id: id, sessionID: event.sessionID, label: Self.label(forAgentType: event.agentType),
                project: event.project, started: now, lastSeen: now, waitingForYou: false
            ))
            return nil
        case .subagentStop:
            if let id = event.agentID { clones.removeAll { $0.id == id } }
            return nil
        case .stop, .stopFailure:
            // A main-session stop ends that session's helpers too.
            clones.removeAll { $0.sessionID == event.sessionID }
            let start = turnStarts.removeValue(forKey: event.sessionID)
            return KaiHookDone(project: event.project, duration: start.map { now.timeIntervalSince($0) }, failed: event.name == .stopFailure)
        case .sessionEnd:
            clones.removeAll { $0.sessionID == event.sessionID }
            turnStarts.removeValue(forKey: event.sessionID)
            return nil
        case .permissionRequest:
            if let id = event.agentID, let index = clones.firstIndex(where: { $0.id == id }) {
                clones[index].waitingForYou = true
                clones[index].lastSeen = now
            }
            return nil
        }
    }

    public mutating func setWaiting(agentID: String?, _ waiting: Bool) {
        guard let agentID, let index = clones.firstIndex(where: { $0.id == agentID }) else { return }
        clones[index].waitingForYou = waiting
    }

    public mutating func expire(now: Date = Date()) {
        clones.removeAll { now.timeIntervalSince($0.lastSeen) > Self.cloneLifetime }
        turnStarts = turnStarts.filter { now.timeIntervalSince($0.value) <= 6 * 3600 }
    }

    public mutating func reset() {
        clones = []
        turnStarts = [:]
    }
}
