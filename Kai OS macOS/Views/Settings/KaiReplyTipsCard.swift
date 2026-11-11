//
//  KaiReplyTipsCard.swift
//  Kai OS macOS
//
//  What Kai learned from how you change its drafts. Each tip can be turned off or deleted, and learning can be
//  switched off. It is all read on this Mac, by the local model.
//

import KaiShared
import SwiftUI

struct KaiReplyTipsCard: View {
    @AppStorage(KaiReplyTips.learnKey) private var learn = true
    @State private var tips: [KaiReplyTip] = KaiReplyTipStore.standard.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learned from your edits").font(KaiFont.captionStrong).foregroundStyle(KaiColor.textTertiary).textCase(.uppercase)
            Toggle("Learn how I write from the changes I make to drafts", isOn: $learn).kaiSwitch()
            Text("When you change a draft before using it, Kai's local model notes how (shorter, no greeting, a sign-off you prefer), never what the message said, and uses it in later drafts. Your writing stays on this Mac.")
                .font(KaiFont.caption2Strong).foregroundStyle(KaiColor.textTertiary)
            if tips.isEmpty {
                Text("Nothing yet. Edit a few drafts and tips appear here.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(tips) { tip in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { tip.enabled }, set: { set(tip.id, enabled: $0) })).labelsHidden().kaiSwitch().controlSize(.small)
                    Text(tip.text).font(.callout).foregroundStyle(tip.enabled ? Color.primary : Color.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { remove(tip.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Delete this tip")
                }
            }
            if !tips.isEmpty {
                Button("Forget all of them") { tips = []; persist() }.controlSize(.small)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kaiLiquidGlass(KaiColor.cyan, radius: 20, glow: 0.18)
        .onAppear { tips = KaiReplyTipStore.standard.load() }
    }

    private func persist() { try? KaiReplyTipStore.standard.save(tips) }
    private func remove(_ id: String) { tips.removeAll { $0.id == id }; persist() }
    private func set(_ id: String, enabled: Bool) {
        tips = tips.map { var t = $0; if t.id == id { t.enabled = enabled }; return t }
        persist()
    }
}
