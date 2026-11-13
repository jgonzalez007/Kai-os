//
//  WritingStyleSetupView.swift
//  Kai OS macOS
//
//  Learns how the user writes, when they ask, and lets them read and edit the result.
//

import KaiActions
import KaiLocalAI
import KaiLocalData
import KaiShared
import SwiftUI

/// Abstracted so the flow can be tested without the user's real sent mail.
protocol KaiSentMailProviding: Sendable {
    func recentBodies() async throws -> [String]
}

struct KaiSystemSentMailProvider: KaiSentMailProviding {
    func recentBodies() async throws -> [String] {
        try await KaiMailSent.recentBodies()
    }
}

@MainActor
final class KaiWritingStyleController: ObservableObject {
    @Published var style = ""
    @Published private(set) var isLearning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sampleCount: Int?

    /// These are replaced by the self-test, so it never touches real mail or the saved style.
    var mailProvider: any KaiSentMailProviding = KaiSystemSentMailProvider()
    var store = KaiWritingStyleStore.standard
    var samplesStore = KaiWritingSamplesStore.standard

    private let appState: AppState
    private let ollama = KaiOllamaClient()

    init(appState: AppState) {
        self.appState = appState
        style = store.load() ?? ""
    }

    /// The style drafts should use, or nil when there isn't one.
    var activeStyle: String? {
        let trimmed = style.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func reload() {
        style = store.load() ?? ""
    }

    func save() {
        do {
            try store.save(style)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        style = ""
        sampleCount = nil
        samplesStore.clear()
        save()
    }

    func learn() {
        guard !isLearning else { return }
        isLearning = true
        errorMessage = nil
        Task {
            defer { isLearning = false }
            do {
                let samples = try await mailProvider.recentBodies().compactMap(KaiSentMailCleaner.ownText)
                guard samples.count >= KaiStylePrompt.minimumSamples else {
                    errorMessage = "Kai OS found too little sent mail to learn from. It needs at least \(KaiStylePrompt.minimumSamples) messages you wrote."
                    return
                }
                if !appState.chatModels.contains(appState.selectedModel) { try await appState.refreshChatModels() }
                guard !appState.selectedModel.isEmpty else { throw KaiOllamaError.noChatModel }
                var text = ""
                // No tools are offered, because even sent mail can carry text from someone else.
                for try await event in ollama.stream(model: KaiModelTag.name(from: appState.selectedModel), messages: KaiStylePrompt.messages(samples: samples), tools: [], temperature: 0.2) {
                    if case .text(let delta) = event { text += delta }
                }
                let learned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !learned.isEmpty else {
                    errorMessage = "The model returned nothing. Try again."
                    return
                }
                style = learned
                sampleCount = samples.count
                try? samplesStore.save(samples)
                save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct KaiWritingStyleSection: View {
    @ObservedObject var controller: KaiWritingStyleController

    var body: some View {
        Section("Writing Style") {
            Text("Email replies follow this. Kai OS can learn it from your recent sent mail, using only words you wrote, and it stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $controller.style)
                .font(.callout)
                .frame(minHeight: 110)
            if let count = controller.sampleCount {
                Text("Learned from \(count) sent messages. Edit anything that's off.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Learn from Sent Mail", action: controller.learn).disabled(controller.isLearning)
                if controller.isLearning { ProgressView().controlSize(.small) }
                Spacer()
                Button("Clear", action: controller.clear).disabled(controller.isLearning || controller.activeStyle == nil)
                Button("Save", action: controller.save).disabled(controller.isLearning)
            }
        }
    }
}
