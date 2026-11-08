//
//  KaiHealthView.swift
//  Kai OS macOS
//
//  A status page: what works, what needs attention. The logic is KaiHealth in KaiShared.
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import KaiShared
import KaiLocalAI

struct KaiHealthView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = KaiPermissionsModel.shared
    @ObservedObject private var briefing: KaiMorningCardsController
    @State private var ollamaModels: [String]?
    @State private var checking = false
    @State private var startingOllama = false
    @State private var startMessage: String?

    init(briefing: KaiMorningCardsController) {
        self.briefing = briefing
    }

    private var items: [KaiHealthItem] {
        KaiHealth.items(KaiHealthInputs(
            ollamaModels: ollamaModels,
            selectedModel: appState.selectedModel,
            permissionsMissing: permissions.missingCount,
            calendarConnected: appState.calendarConnected,
            mailConnected: appState.mailConnected,
            notesConnected: appState.notesConnected,
            useCloud: appState.useCloud,
            hasOpenAIKey: KaiKeychain.hasApiKey(for: "openai"),
            hasAnthropicKey: KaiKeychain.hasApiKey(for: "anthropic"),
            briefingCardCount: briefing.activeCards.count,
            briefingError: briefing.errorMessage,
            briefingIsRunning: briefing.isGenerating,
            knowledgeDocuments: appState.knowledgeDocumentCount,
            nightShift: appState.nightShift,
            nightShiftRecord: appState.nightShiftRecord
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Health").font(KaiFont.title3)
                Spacer()
                Button(checking ? "Checking…" : "Check again") { Task { await check() } }
                    .disabled(checking)
            }
            .padding(16)
            Divider()
            List(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(item.status))
                        .foregroundStyle(color(item.status))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(KaiFont.bodyStrong)
                        Text(item.detail).font(KaiFont.caption).foregroundStyle(.secondary)
                        if item.id == "ollama" && ollamaModels == nil { ollamaActions }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .task { await check() }
    }

    /// Ollama cannot be reached: offer to start it, or to install it when it is not on this Mac.
    @ViewBuilder
    private var ollamaActions: some View {
        HStack(spacing: 8) {
            if KaiOllamaSetup.isInstalled() {
                Button(startingOllama ? "Starting…" : "Start Ollama") { Task { await startOllama() } }
                    .disabled(startingOllama)
            } else {
                Button("Download Ollama") { NSWorkspace.shared.open(KaiOllamaSetup.downloadPage) }
            }
            if let startMessage {
                Text(startMessage).font(KaiFont.caption).foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        .padding(.top, 2)
    }

    /// Opens the Ollama app, then waits up to 30 seconds for its server to answer.
    private func startOllama() async {
        startingOllama = true
        startMessage = nil
        defer { startingOllama = false }
        for path in KaiOllamaSetup.appPaths() where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            break
        }
        for _ in 0..<15 {
            try? await Task.sleep(for: .seconds(2))
            if let models = try? await KaiOllamaClient().listModels() {
                ollamaModels = models.map(\.name)
                try? await appState.refreshChatModels()
                return
            }
        }
        startMessage = "Ollama did not answer in 30 seconds. Open it yourself, then press Check again."
    }

    private func check() async {
        checking = true
        defer { checking = false }
        appState.refreshKnowledgeCounts()
        ollamaModels = try? await KaiOllamaClient().listModels().map(\.name)
    }

    private func icon(_ status: KaiHealthItem.Status) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .off: return "circle.dashed"
        }
    }

    private func color(_ status: KaiHealthItem.Status) -> Color {
        switch status {
        case .ok: return .green
        case .attention: return .orange
        case .off: return .secondary
        }
    }
}
