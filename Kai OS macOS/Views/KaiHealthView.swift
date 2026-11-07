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
            briefingIsRunning: briefing.isGenerating
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
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.inset)
        }
        .task { await check() }
    }

    private func check() async {
        checking = true
        defer { checking = false }
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
