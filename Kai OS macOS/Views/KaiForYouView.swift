//
//  KaiForYouView.swift
//  Kai OS macOS
//
//  The morning cards. Reading them is free; anything that acts waits for a click here.
//

import KaiActions
import KaiLocalData
import SwiftUI

struct KaiForYouView: View {
    @ObservedObject var controller: KaiMorningCardsController
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("For You").font(.title).fontWeight(.bold)
                    Text("Refreshed each morning from your calendar and unread mail.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.isGenerating { ProgressView().controlSize(.small) }
                Button("Refresh", action: controller.generate)
                    .disabled(controller.isGenerating || !controller.hasSources)
            }
            .padding()
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if !controller.hasSources {
            emptyState(
                icon: "lock.shield",
                title: "Nothing connected yet",
                detail: "Turn on Calendar or Apple Mail, and Kai OS will prepare cards each morning."
            ) {
                Button("Open Permissions") { appState.activeSidebar = "Permissions" }.buttonStyle(.borderedProminent)
            }
        } else if controller.activeCards.isEmpty {
            emptyState(
                icon: "sun.max",
                title: controller.isGenerating ? "Looking through today…" : "Nothing needs you right now",
                detail: "Cards appear here the first time Kai OS is running after \(KaiBriefingSchedule.startHour) each morning."
            ) { EmptyView() }
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(controller.activeCards) { KaiMorningCardRow(card: $0, controller: controller) }
                }
                .padding()
            }
        }
    }

    private func emptyState<Actions: View>(icon: String, title: String, detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.title2).fontWeight(.semibold)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            actions()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KaiMorningCardRow: View {
    let card: KaiMorningCard
    @ObservedObject var controller: KaiMorningCardsController

    private var icon: String {
        switch card.kind {
        case .note: return "lightbulb"
        case .reply: return "arrowshape.turn.up.left"
        case .action(let actionCard): return actionCard.action.iconName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(.purple).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title).fontWeight(.semibold)
                    if !card.why.isEmpty { Text(card.why).font(.callout).foregroundStyle(.secondary) }
                    details
                }
                Spacer()
                Button { controller.dismiss(card.id) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Dismiss")
            }
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var details: some View {
        switch card.kind {
        case .note:
            EmptyView()
        case .reply(let mail):
            Text("\(mail.sender): \(mail.subject)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
        case .action(let actionCard):
            ForEach(actionCard.action.details.filter { $0.label != "Title" && $0.label != "Text" }, id: \.label) { row in
                Text("\(row.label): \(row.value)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch card.kind {
        case .note:
            EmptyView()
        case .reply(let mail):
            Button("Draft Reply") { KaiNotchWindowController.shared.startReply(to: mail) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .action(let actionCard):
            switch actionCard.state {
            case .pending:
                HStack {
                    Button("Approve") { controller.approve(card.id) }.buttonStyle(.borderedProminent).controlSize(.small)
                    Button("Decline") { controller.decline(card.id) }.controlSize(.small)
                }
            case .running:
                ProgressView().controlSize(.small)
            case .declined:
                EmptyView()
            case .succeeded(let detail):
                Label(detail, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .failed(let detail):
                Label(detail, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
