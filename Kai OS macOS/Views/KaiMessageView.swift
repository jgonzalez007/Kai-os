//
//  KaiMessageView.swift
//  Kai OS macOS
//
//  Message bubbles — user, assistant, error, and action cards
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import KaiActions

struct MessageBubbleView: View {
    let message: Message
    /// True for the reply that is still being written, so its text can fade in.
    var isStreaming = false
    @AppStorage(KaiMotion.key) private var motion = true
    
    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.text, options: options))
            ?? AttributedString(message.text)
    }
    
    var body: some View {
        if let card = message.actionCard {
            KaiActionCardView(messageID: message.id, card: card)
        } else if message.kind == .notice {
            noticeBubble
        } else if message.kind == .error {
            errorBubble
        } else {
            defaultBubble
        }
    }
    
    // ── Notice (system message) ──
    private var noticeBubble: some View {
        HStack {
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(rendered)
                    .font(KaiFont.body)
                    .foregroundStyle(KaiColor.textPrimary)
                    .padding(KaiSpacing.regular)
                    .background(
                        RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                            .fill(KaiColor.primary.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                                    .stroke(KaiColor.primary.opacity(0.2), lineWidth: 1)
                            )
                    )
                
                Text(message.timestamp, style: .time)
                    .font(KaiFont.caption2Strong)
                    .foregroundStyle(KaiColor.textTertiary)
            }
            .padding(KaiSpacing.regular)
            .frame(maxWidth: 520, alignment: .trailing)
            .background(KaiColor.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge))
        }
    }
    
    // ── Error ──
    private var errorBubble: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(KaiColor.error)
                .font(KaiFont.labelStrong)
            
            Text(rendered)
                .font(KaiFont.body)
                .foregroundStyle(KaiColor.error)
                .textSelection(.enabled)
            
            Spacer()
        }
        .padding(KaiSpacing.regular)
        .background(
            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                .fill(KaiColor.error.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                        .stroke(KaiColor.error.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(maxWidth: 520)
    }
    
    // ── Default (assistant) bubble ──
    private var defaultBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            // ── Avatar ──
            VStack {
                Image(systemName: "sparkles")
                    .font(KaiFont.caption2Strong)
                    .foregroundStyle(KaiColor.primary)
                    .padding(6)
                    .background(KaiColor.primary.opacity(0.1), in: Circle())
                    .frame(width: 32, height: 32)
            }
            
            // ── Content ──
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Kai").font(KaiFont.labelStrong)
                        .foregroundStyle(KaiColor.textPrimary)
                    
                    Text(message.timestamp, style: .time)
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                    
                    Spacer()
                    
                    // ── Status ──
                    if message.status != nil {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                            .scaleEffect(0.8)
                    }
                }
                
                // ── Text ──
                if !message.text.isEmpty {
                    Group {
                        if motion && isStreaming {
                            KaiRevealText(text: rendered, streaming: true)
                        } else {
                            Text(rendered)
                        }
                    }
                    .font(KaiFont.body)
                    .textSelection(.enabled)
                    .foregroundStyle(KaiColor.textPrimary)
                } else if let status = message.status {
                    Text(status)
                        .font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textSecondary)
                }
                
                // ── Image attachment ──
                if let data = message.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 200)
                        .cornerRadius(KaiSpacing.cornerRadiusSmall)
                        .overlay(
                            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusSmall)
                                .strokeBorder(KaiColor.border.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.top, 4)
                }
            }
            
            Spacer(minLength: 40)
        }
        .padding(KaiSpacing.cardPadding)
        .frame(maxWidth: 560, alignment: .leading)
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
}

// MARK: - Action Card

struct KaiActionCardView: View {
    let messageID: String
    let card: KaiActionCard
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ── Card Header ──
            HStack(spacing: 10) {
                Image(systemName: card.action.iconName)
                    .font(KaiFont.labelStrong)
                    .foregroundStyle(KaiColor.primary)
                    .padding(8)
                    .background(KaiColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.action.heading).font(KaiFont.bodyStrong)
                    Text("Review before approving").font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                }
                Spacer()
            }
            
            // ── Details Grid ──
            ScrollView {
                Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(card.action.details, id: \.label) { row in
                        GridRow {
                            Text(row.label).font(KaiFont.caption2Strong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Text(row.value).font(KaiFont.caption)
                                .textSelection(.enabled)
                                .foregroundStyle(KaiColor.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            
            // ── Status / Actions ──
            actionStatus
        }
        .padding(KaiSpacing.cardPadding)
        .background(
            LinearGradient(
                colors: [KaiColor.primary.opacity(0.06), KaiColor.secondary.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .cornerRadius(KaiSpacing.cornerRadiusLarge)
            .overlay(
                RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                    .stroke(KaiColor.primary.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: KaiColor.primary.opacity(0.08), radius: 8, x: 0, y: 3)
        )
    }
    
    @ViewBuilder
    private var actionStatus: some View {
        switch card.state {
        case .pending:
            HStack(spacing: 12) {
                Button("Approve") {
                    appState.approveAction(messageID: messageID)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .tint(KaiColor.success)
                
                Button("Decline") {
                    appState.declineAction(messageID: messageID)
                }
                .buttonBorderShape(.roundedRectangle)
                
                Spacer()
                
                Text("Nothing happens until you approve").font(KaiFont.caption2Strong)
                    .foregroundStyle(KaiColor.textTertiary)
            }
            
        case .running:
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                Text("Running...").font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.textSecondary)
            }
            
        case .declined:
            HStack {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(KaiColor.textTertiary)
                Text("Declined. Nothing was done.").font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.textTertiary)
            }
            
        case .succeeded(let detail):
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(KaiColor.success)
                Text(detail).font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.success)
            }
            
        case .failed(let detail):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(KaiColor.error)
                Text(detail).font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.error)
            }
        }
    }
}
