//
//  KaiForYouView.swift
//  Kai OS macOS
//
//  The morning cards — modern, adaptive, with clean styling
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import KaiActions
import KaiLocalData
import SwiftUI

struct KaiForYouView: View {
    @ObservedObject var controller: KaiMorningCardsController
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack(spacing: 12) {
                Image(systemName: "sun.max")
                    .font(KaiFont.labelStrong)
                    .foregroundStyle(KaiColor.warning)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("For You").font(KaiFont.title3)
                    Text("Refreshed each morning from your calendar, mail, and notes").font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textTertiary)
                }
                
                Spacer()
                
                if controller.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                        .scaleEffect(0.7)
                }
                
                Button("Refresh") { controller.generate() }
                    .disabled(controller.isGenerating || !controller.hasSources)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
            }
            .padding(KaiSpacing.regular)
            
            // ── Error ──
            if let error = controller.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(KaiColor.warning)
                        .font(KaiFont.caption2Strong)
                    Text(error).font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textSecondary)
                }
                .padding(KaiSpacing.regular)
                .background(KaiColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius))
            }
            
            Divider().kaiDivider()
            
            // ── Content ──
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
                Button("Open Permissions") { appState.openPreferences(.permissions) }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
            }
        } else if controller.activeCards.isEmpty {
            emptyState(
                icon: controller.isGenerating ? "arrow.triangle.2.circlepath" : "sun.max",
                title: controller.isGenerating ? "Looking through today..." : "Nothing needs you right now",
                detail: "Cards appear here the first time Kai OS is running after \(KaiBriefingSchedule.startHour) each morning."
            ) { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(controller.activeCards) { card in
                        KaiMorningCardRow(card: card, controller: controller)
                    }
                }
                .padding(KaiSpacing.regular)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func emptyState<Actions: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(KaiFont.title2)
                .foregroundStyle(KaiColor.textTertiary)
                .padding(.bottom, 8)
            
            Text(title).font(KaiFont.bodyStrong)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            
            Text(detail).font(KaiFont.caption)
                .foregroundStyle(KaiColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            
            actions()
        }
        .padding(KaiSpacing.xxlarge)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(KaiFont.caption2Strong)
                    .foregroundStyle(KaiColor.primary)
                    .padding(6)
                    .background(KaiColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let urgency = card.urgency { UrgencyPill(urgency: urgency) }
                        Text(card.title).font(KaiFont.bodyStrong)
                    }
                    
                    if !card.why.isEmpty {
                        Text(card.why).font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textTertiary)
                    }
                    
                    details
                }
                
                Spacer()
                
                Button { controller.dismiss(card.id) } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(KaiColor.textTertiary)
                        .font(KaiFont.caption2Strong)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            
            actions
        }
        .padding(KaiSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                .fill(KaiColor.surfaceBg)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                        .stroke(KaiColor.border.opacity(0.3), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var details: some View {
        switch card.kind {
        case .note:
            EmptyView()
        case .reply(let mail):
            Text("\(mail.sender): \(mail.subject)").font(KaiFont.caption)
                .foregroundStyle(KaiColor.textTertiary)
                .lineLimit(2)
        case .action(let actionCard):
            ForEach(actionCard.action.details.filter { $0.label != "Title" && $0.label != "Text" }, id: \.label) { row in
                HStack(spacing: 6) {
                    Text(row.label).font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                    Text(row.value).font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textSecondary)
                    Spacer()
                }
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
                .buttonBorderShape(.roundedRectangle)
                .controlSize(.small)
        case .action(let actionCard):
            switch actionCard.state {
            case .pending:
                HStack(spacing: 10) {
                    Button("Approve") { controller.approve(card.id) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle)
                        .controlSize(.small)
                        .tint(KaiColor.success)
                    
                    Button("Decline") { controller.decline(card.id) }
                        .buttonBorderShape(.roundedRectangle)
                        .controlSize(.small)
                }
            case .running:
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                    Text("Running...").font(KaiFont.captionStrong)
                        .foregroundStyle(KaiColor.textSecondary)
                }
            case .declined:
                EmptyView()
            case .succeeded(let detail):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(KaiColor.success)
                    Text(detail).font(KaiFont.captionStrong)
                        .foregroundStyle(KaiColor.success)
                }
            case .failed(let detail):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(KaiColor.error)
                    Text(detail).font(KaiFont.captionStrong)
                        .foregroundStyle(KaiColor.error)
                }
            }
        }
    }
}
