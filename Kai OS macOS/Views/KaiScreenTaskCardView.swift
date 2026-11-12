//
//  KaiScreenTaskCardView.swift
//  Kai OS macOS
//
//  The card in the chat when Claude asks to do something on the screen. Nothing happens until the person presses
//  Start. Claude can't press it: the buttons are in Kai's own window, which Sidekick can't see or click.
//

import SwiftUI

struct KaiScreenTaskCardView: View {
    @EnvironmentObject var appState: AppState
    let messageID: String
    let card: KaiScreenTaskCard

    private var askEach: Bool { appState.agent.mode == .askEach }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Do this on your screen", systemImage: "cursorarrow.motionlines").font(KaiFont.captionStrong)
            Text(card.task).font(KaiFont.body).textSelection(.enabled)
            switch card.state {
            case .asking:
                Text(askEach ? "Kai will ask before every click and keystroke. You can change this on the Sidekick page." : "Kai will click and type on its own, and still ask before sending or quitting. You can change this on the Sidekick page.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button("Start") { appState.decideScreenTask(messageID: messageID, start: true) }.kaiProminent()
                    Button("Not now") { appState.decideScreenTask(messageID: messageID, start: false) }
                }
            case .running:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(appState.agent.statusLine).font(KaiFont.caption).foregroundStyle(.secondary) }
            case .finished(let result):
                Label(result, systemImage: "flag.checkered").font(KaiFont.caption).foregroundStyle(.secondary)
            case .declined:
                Text("Not started.").font(KaiFont.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
