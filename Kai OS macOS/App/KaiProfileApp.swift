//
//  KaiProfileApp.swift
//  Kai OS macOS
//
//  Builds "what Kai knows about you" from the knowledge base with the local model. Nothing leaves
//  the Mac. The text and its rules are in KaiKnowledge (KaiProfile) and covered by KaiChecksTests.
//

import Foundation
import KaiKnowledge
import KaiLocalAI
import KaiShared

extension AppState {
    /// Rebuilds the portrait. A failure keeps the one already there and says why.
    @discardableResult
    func rebuildProfileNow() async -> Bool {
        guard !isBuildingProfile else { return false }
        isBuildingProfile = true
        profileMessage = nil
        defer { isBuildingProfile = false }
        guard let store = openKnowledgeStore(), let documents = try? store.documents(limit: 300, maxText: 4_000), !documents.isEmpty else {
            profileMessage = "Nothing to learn from yet. Add a note on the Knowledge setup page, or index your sources."
            return false
        }
        do {
            let client = KaiOllamaClient()
            if !chatModels.contains(selectedModel) { try await refreshChatModels() }
            guard let model = chatModels.contains(selectedModel) ? selectedModel : chatModels.first else { throw KaiOllamaError.noChatModel }
            let prompt = KaiProfilePrompt.messages(documents: documents, existing: profile, now: Date())
            var text = ""
            // No tools: the sources are untrusted, so the model only writes text that is then checked.
            let stream = client.stream(model: KaiModelTag.name(from: model),
                                       messages: [KaiOllamaMessage(role: "system", content: prompt.system), KaiOllamaMessage(role: "user", content: prompt.user)],
                                       tools: [], temperature: 0.2)
            for try await event in stream { if case .text(let delta) = event { text += delta } }
            guard let markdown = KaiProfilePrompt.clean(text) else {
                profileMessage = "The model's answer wasn't usable, so the old portrait stays. Try again, or pick a larger model."
                return false
            }
            let built = KaiProfile(markdown: markdown, updatedAt: Date(), documentCount: KaiProfilePrompt.selection(from: documents).count,
                                   edited: profile?.edited ?? false)
            try KaiProfileStore.standard.save(built)
            profile = built
            return true
        } catch {
            profileMessage = "Couldn't update: \(error.localizedDescription)"
            return false
        }
    }

    /// Saves the person's own wording. The next rebuild keeps it.
    func saveProfileEdit(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var next = profile ?? KaiProfile(markdown: "")
        guard clean != next.markdown else { return }
        next.markdown = String(clean.prefix(KaiProfilePrompt.maxProfileLength))
        next.edited = true
        next.updatedAt = Date()
        do { try KaiProfileStore.standard.save(next); profile = next } catch { profileMessage = "Couldn't save: \(error.localizedDescription)" }
    }

    func forgetProfile() {
        KaiProfileStore.standard.delete()
        profile = nil
    }
}
