//
//  KaiMenuStatus.swift
//  Kai Shared
//
//  One summary of how Kai is doing, for the menu bar icon and the strip beside the notch.
//  Plain values in, plain values out, so the rules can be tested.
//

import Foundation

public struct KaiMenuStatusInputs: Equatable, Sendable {
    public enum AI: Equatable, Sendable {
        /// Local model through Ollama. `reachable` is nil until the first check.
        case local(model: String, reachable: Bool?)
        case cloud(model: String)
    }

    public var ai: AI
    public var isWorking: Bool
    public var approvalsWaiting: Int
    public var helperAgents: Int
    public var newCards: Int
    public var updateVersion: String?

    public init(ai: AI, isWorking: Bool = false, approvalsWaiting: Int = 0, helperAgents: Int = 0,
                newCards: Int = 0, updateVersion: String? = nil) {
        self.ai = ai
        self.isWorking = isWorking
        self.approvalsWaiting = approvalsWaiting
        self.helperAgents = helperAgents
        self.newCards = newCards
        self.updateVersion = updateVersion
    }
}

public struct KaiMenuStatus: Equatable, Sendable {
    /// Most urgent first: needsYou, then working, then attention, then idle.
    public enum Level: Equatable, Sendable { case idle, working, needsYou, attention }

    public let level: Level
    public let title: String
    public let symbol: String
    public let lines: [String]
    /// True when the local AI is switched to but cannot be reached.
    public let aiOffline: Bool

    public static func summarize(_ i: KaiMenuStatusInputs) -> KaiMenuStatus {
        var lines: [String] = []
        var offline = false
        switch i.ai {
        case .local(let model, let reachable):
            if reachable == false {
                lines.append("AI: Ollama is not running")
                offline = true
            } else if model.isEmpty {
                lines.append(reachable == nil ? "AI: checking…" : "AI: no model chosen")
            } else {
                lines.append("AI: \(model) on this Mac")
            }
        case .cloud(let model):
            lines.append(model.isEmpty ? "AI: cloud" : "AI: \(model) (cloud)")
        }
        if i.approvalsWaiting > 0 {
            lines.append(i.approvalsWaiting == 1 ? "Claude Code: 1 request waiting for you" : "Claude Code: \(i.approvalsWaiting) requests waiting for you")
        }
        if i.helperAgents > 0 {
            lines.append(i.helperAgents == 1 ? "Claude Code: 1 helper agent running" : "Claude Code: \(i.helperAgents) helper agents running")
        }
        if i.newCards > 0 {
            lines.append(i.newCards == 1 ? "For You: 1 card" : "For You: \(i.newCards) cards")
        }
        if let version = i.updateVersion { lines.append("Update available: \(version)") }

        if i.approvalsWaiting > 0 {
            return KaiMenuStatus(level: .needsYou, title: "Needs your OK", symbol: "hand.raised.fill", lines: lines, aiOffline: offline)
        }
        if i.isWorking {
            return KaiMenuStatus(level: .working, title: "Working", symbol: "waveform", lines: lines, aiOffline: offline)
        }
        if offline {
            return KaiMenuStatus(level: .attention, title: "AI offline", symbol: "exclamationmark.triangle.fill", lines: lines, aiOffline: true)
        }
        return KaiMenuStatus(level: .idle, title: "Ready", symbol: "sparkle", lines: lines, aiOffline: false)
    }
}
