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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Health").font(.system(size: 30, weight: .semibold))
                        Text("What is working, and what needs attention.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(checking ? "Checking…" : "Check again") { Task { await check() } }
                        .disabled(checking)
                        .padding(.top, 6)
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.bottom, 4)

                ForEach(items) { item in card(item) }
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 40).padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
        .background(KaiAmbientBackground())
        .task { await check() }
    }

    private func card(_ item: KaiHealthItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(item.status))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color(item.status))
                .frame(width: 34, height: 34)
                .background(Circle().fill(color(item.status).opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).fontWeight(.semibold)
                Text(item.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if item.id == "ollama" && ollamaModels == nil { ollamaActions }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kaiLiquidGlass(color(item.status), radius: 18, glow: item.status == .ok ? 0.1 : 0.22)
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
        case .ok: return KaiColor.cyan
        case .attention: return KaiColor.magenta
        case .off: return Color.white.opacity(0.45)
        }
    }
}
