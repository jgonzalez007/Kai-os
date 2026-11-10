//
//  KaiTodayCard.swift
//  Kai OS macOS
//
//  Today from the notch: the morning list, most urgent first, in a card under the notch. Each item can be
//  dismissed, or opened in For You, where replies and calendar items are approved and acted on. Nothing is
//  sent or changed from this card.
//

import AppKit
import KaiActions
import SwiftUI

@MainActor
final class KaiTodayController {
    static let shared = KaiTodayController()
    private var panel: KaiResultPanel?

    func show(appState: AppState) {
        if panel == nil {
            let panel = KaiResultPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.onCancel = { [weak self] in self?.close() }
            self.panel = panel
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: KaiTodayCard(cards: appState.morningCards, appState: appState, close: { [weak self] in self?.close() }))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.frame {
            let width = min(560, frame.width - 80), height = min(460, frame.height - 160)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 40, width: width, height: height), display: true)
        }
        KaiNotchWindowController.shared.collapse()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }
}

struct KaiTodayCard: View {
    @ObservedObject var cards: KaiMorningCardsController
    let appState: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.system(size: 19, weight: .semibold))
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if cards.isGenerating { ProgressView().controlSize(.small) }
                Button { cards.generate() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Make today's list again").disabled(!cards.hasSources || cards.isGenerating)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }.buttonStyle(.plain).help("Close")
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let items = cards.activeCards
                    if items.isEmpty {
                        Text(cards.hasSources ? "Nothing needs you yet today. Night Shift makes this list, or press refresh." : "Connect Calendar or Mail in Kai OS settings, and Kai lists what needs you each morning.")
                            .foregroundStyle(.white.opacity(0.7)).padding(.top, 8)
                    }
                    ForEach(items.prefix(6)) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                if let urgency = card.urgency { UrgencyPill(urgency: urgency) }
                                Text(card.title).fontWeight(.semibold).lineLimit(2)
                                Spacer(minLength: 6)
                                Button("Dismiss") { cards.dismiss(card.id) }.buttonStyle(.plain).font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                            if !card.why.isEmpty { Text(card.why).font(.callout).foregroundStyle(.white.opacity(0.7)).lineLimit(3) }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(22)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Button {
                    appState.activeSidebar = "ForYou"
                    KaiNotchWindowController.shared.openMainWindow()
                    close()
                } label: {
                    Label("Open For You to act on these", systemImage: "arrow.up.forward.app").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(KaiColor.liquidBlue))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("From your calendar and mail, read on this Mac.").font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }
}
