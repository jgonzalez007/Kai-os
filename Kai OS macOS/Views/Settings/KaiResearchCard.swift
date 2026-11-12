//
//  KaiResearchCard.swift
//  Kai OS macOS
//
//  The switches for chat on Claude. Claude can search mail, notes and so on with Kai's tools, but only the sources
//  turned on here, and only after the main switch. Everything it reads is sent to Anthropic, so all of them start off.
//

import SwiftUI
import KaiAgent

struct KaiResearchCard: View {
    @AppStorage(KaiResearch.consentKey) private var consent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude chat research").font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick Claude as the chat model and it can research across several steps: search your mail, open the messages that matter, search again, then answer. It uses your Claude subscription through the Claude Code tool on this Mac, and only the sources you turn on below. It can't send or delete anything.")
                    .font(.callout)
                Label("Your questions, and whatever the tools find in the sources you turn on, are sent to Anthropic. A local model keeps everything on this Mac.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Toggle("I understand, and I want chat on Claude to use these sources", isOn: $consent).kaiSwitch().tint(.green)
                Divider().overlay(Color.white.opacity(0.08))
                ForEach(KaiResearchSource.allCases, id: \.rawValue) { SourceRow(source: $0).disabled(!consent) }
                Text("Each source starts off. If one is off, Claude is told so and carries on with the others. Mail also needs your Mailbox access setting to allow reading whole mailboxes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .kaiGlassSurface(radius: 16)
        }
    }

    private struct SourceRow: View {
        let source: KaiResearchSource
        @AppStorage private var on: Bool

        init(source: KaiResearchSource) {
            self.source = source
            _on = AppStorage(wrappedValue: false, source.key)
        }

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title).fontWeight(.medium)
                    Text(source.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $on).labelsHidden().kaiSwitch().tint(.green)
            }
        }
    }
}
