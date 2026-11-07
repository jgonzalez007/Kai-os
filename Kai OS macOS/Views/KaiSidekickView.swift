//
//  KaiSidekickView.swift
//  Kai OS macOS
//
//  Give Kai a task and it operates your Mac for you, one approved step at a time.
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import KaiAgent

struct KaiSidekickView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent: KaiAgentController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sidekick").font(KaiFont.title3)

                Text("Describe a task and Kai will do it in your other apps by looking at the screen and using the mouse and keyboard, with a ring where it clicks. It uses a local model, so what's on your screen never leaves this Mac.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                TextEditor(text: $agent.task)
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 110)
                    .padding(6)
                    .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(agent.isRunning)
                    .overlay(alignment: .topLeading) {
                        if agent.task.isEmpty {
                            Text("For example: open Notes and create a note called Shopping with milk and eggs")
                                .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                        }
                    }

                Picker("Control", selection: $agent.mode) {
                    Text("Ask me before every action").tag(KaiAgentMode.askEach)
                    Text("Run on its own").tag(KaiAgentMode.auto)
                }
                .pickerStyle(.radioGroup)
                .disabled(agent.isRunning)

                Text(agent.mode == .askEach
                     ? "Every click, keystroke and shortcut waits for your Approve."
                     : "Clicks, typing and scrolling run by themselves. Kai still asks before Return, Delete, quitting or closing, and before typing a new line. Use this only for tasks where a wrong click is harmless.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                HStack {
                    if agent.isRunning {
                        Button("Stop") { agent.stop() }.tint(.red)
                    } else {
                        Button("Start") { agent.start(appState: appState) }
                            .buttonStyle(.borderedProminent)
                            .disabled(agent.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if agent.isRunning { ProgressView().controlSize(.small) }
                }

                if let message = agent.message {
                    Text(message).font(KaiFont.caption).foregroundStyle(.orange)
                }

                GroupBox("Safety") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Esc, the Stop button, or using your own mouse or keyboard stops it at once.")
                        Text("• It never works in Terminal, System Settings, password managers or Keychain Access, and never while Kai's own window is in front.")
                        Text("• It stops after 30 steps or 10 minutes.")
                        Text("• Everything it proposes or does is logged in ~/Library/Application Support/Kai OS/agent-log.jsonl. Screenshots are not saved.")
                        Text("• Text on screen is treated as untrusted. Kai won't act on instructions it reads there.")
                    }
                    .font(KaiFont.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                if !agent.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened").font(KaiFont.bodyStrong)
                        ForEach(agent.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: icon(line.kind)).foregroundStyle(color(line.kind)).frame(width: 16)
                                Text(line.text).font(KaiFont.caption)
                                    .foregroundStyle(line.kind == .thought ? .secondary : .primary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func icon(_ kind: KaiAgentController.LineKind) -> String {
        switch kind {
        case .thought: return "bubble.left"
        case .proposed: return "questionmark.circle"
        case .performed: return "checkmark.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        case .outcome: return "flag.checkered"
        }
    }

    private func color(_ kind: KaiAgentController.LineKind) -> Color {
        switch kind {
        case .performed: return .green
        case .problem: return .orange
        case .outcome: return .purple
        default: return .secondary
        }
    }
}
