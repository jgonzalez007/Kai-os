//
//  KaiAboutYouView.swift
//  Kai OS macOS
//
//  The first face of Knowledge: what Kai knows about you (a portrait the local model writes from your
//  knowledge base, and that you can correct) and what to focus on today. Chat and the morning briefing
//  read the same portrait.
//

import KaiActions
import KaiKnowledge
import SwiftUI

struct KaiAboutYouView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var cards: KaiMorningCardsController
    var documentCount: Int

    @State private var editing = false
    @State private var draft = ""
    @State private var confirmForget = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            portraitCard
            focusCard.frame(width: 340)
        }
    }

    // MARK: Portrait

    private var portraitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(KaiColor.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text("What Kai knows about you").font(.system(size: 18, weight: .semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if appState.isBuildingProfile {
                    ProgressView().controlSize(.small)
                    Text("Reading…").font(.caption).foregroundStyle(.secondary)
                } else if editing {
                    Button("Cancel") { editing = false }.controlSize(.small)
                    Button("Save") { appState.saveProfileEdit(draft); editing = false }
                        .controlSize(.small).buttonStyle(.borderedProminent).tint(KaiColor.liquidBlue)
                } else {
                    if appState.profile != nil {
                        Button { draft = appState.profile?.markdown ?? ""; editing = true } label: { Label("Correct", systemImage: "pencil") }.controlSize(.small)
                    }
                    Button { Task { await appState.rebuildProfileNow() } } label: {
                        Label(appState.profile == nil ? "Build it now" : "Update", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small).disabled(documentCount == 0)
                }
            }
            if let message = appState.profileMessage {
                Text(message).font(.caption).foregroundStyle(KaiColor.warning)
            }
            Divider().overlay(Color.white.opacity(0.1))
            if editing {
                TextEditor(text: $draft)
                    .font(.system(size: 13)).scrollContentBackground(.hidden)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                Text("Write it your way. Kai keeps your wording when it updates this.").font(.caption).foregroundStyle(.secondary)
            } else if let profile = appState.profile {
                ScrollView { rendered(profile.markdown).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button("Teach Kai something") { appState.openPreferences(.knowledge) }.controlSize(.small)
                    Spacer()
                    if confirmForget {
                        Text("Delete this portrait?").font(.caption).foregroundStyle(.secondary)
                        Button("Delete", role: .destructive) { appState.forgetProfile(); confirmForget = false }.controlSize(.small)
                        Button("Keep") { confirmForget = false }.controlSize(.small)
                    } else {
                        Button("Forget this") { confirmForget = true }.controlSize(.small).foregroundStyle(.secondary)
                    }
                }
            } else {
                empty
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.1)
    }

    private var subtitle: String {
        guard let profile = appState.profile else { return "Not written yet" }
        let when = profile.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return "From \(profile.documentCount) documents · updated \(when)" + (profile.edited ? " · includes your corrections" : "")
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Kai hasn't learned about you yet").font(.headline)
            Text("Tell Kai who you are and what matters to you on the Knowledge setup page, and connect Notes, Calendar or Mail. Night Shift then writes a portrait here every night. Chat and your morning list use it to tell what is urgent for you.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack {
                Button("Tell Kai about you") { appState.openPreferences(.knowledge) }.buttonStyle(.borderedProminent).tint(KaiColor.liquidBlue)
                if documentCount > 0 { Button("Build it now") { Task { await appState.rebuildProfileNow() } } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Headings and bullets only: the portrait is written in that shape.
    private func rendered(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("## ") {
                    Text(String(text.dropFirst(3))).font(.system(size: 13, weight: .semibold)).foregroundStyle(KaiColor.cyan).padding(.top, 8)
                } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(String(text.dropFirst(2)))).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled)
                    }
                } else if !text.isEmpty {
                    Text(inline(text)).font(.system(size: 14)).textSelection(.enabled)
                }
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: Focus

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scope").foregroundStyle(KaiColor.magenta)
                Text("Focus today").font(.system(size: 18, weight: .semibold))
                Spacer()
                if cards.isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Button { cards.generate() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Make today's list again").disabled(!cards.hasSources)
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            let items = cards.activeCards
            if items.isEmpty {
                Text(cards.hasSources
                     ? "Nothing yet today. Night Shift makes this list, or press refresh."
                     : "Connect Calendar or Mail under Knowledge setup, and Kai will list what needs you today.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open For You") { appState.activeSidebar = "ForYou" }.controlSize(.small)
            } else {
                ForEach(items.prefix(6)) { card in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let urgency = card.urgency { UrgencyPill(urgency: urgency) }
                            Text(card.title).fontWeight(.medium).lineLimit(2)
                        }
                        if !card.why.isEmpty { Text(card.why).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                }
                Button("Open For You to act on these") { appState.activeSidebar = "ForYou" }.controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .kaiLiquidGlass(KaiColor.magenta, radius: 18, glow: 0.1)
    }
}

struct UrgencyPill: View {
    let urgency: KaiMorningCard.Urgency

    var body: some View {
        Text(urgency == .urgent ? "Urgent" : "Important")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((urgency == .urgent ? KaiColor.magenta : KaiColor.warning).opacity(0.25)))
            .foregroundStyle(urgency == .urgent ? KaiColor.magenta : KaiColor.warning)
    }
}
