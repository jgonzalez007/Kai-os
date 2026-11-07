//
//  KaiMailView.swift
//  Kai OS macOS
//
//  Modern mail view — card-style messages, smart search
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiMailView: View {
    @EnvironmentObject var appState: AppState
    
    private var query: String { appState.mailQuery }
    
    private var visibleMessages: [MailMessage] {
        guard !query.isEmpty else { return appState.mailMessages }
        return appState.mailMessages.filter {
            $0.subject.localizedCaseInsensitiveContains(query)
                || $0.from.localizedCaseInsensitiveContains(query)
        }
    }
    
    var body: some View {
        Group {
            if appState.mailConnected {
                VStack(spacing: 0) {
                    // ── Header ──
                    HStack(spacing: 12) {
                        Image(systemName: "envelope")
                            .font(KaiFont.labelStrong)
                            .foregroundStyle(KaiColor.primary)
                        
                        Text("Mail").font(KaiFont.title3)
                        Spacer()
                        
                        if appState.mailState == .loading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                                .scaleEffect(0.7)
                        }
                        
                        Button("Refresh") {
                            appState.refreshMail()
                        }
                        .buttonBorderShape(.roundedRectangle)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, KaiSpacing.regular)
                    .padding(.vertical, 12)
                    
                    // ── Search ──
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(KaiColor.textTertiary)
                        
                        TextField("Search mail", text: $appState.mailQuery)
                            .textFieldStyle(.plain)
                            .kaiInput()
                        
                        if !appState.mailQuery.isEmpty {
                            Button {
                                appState.mailQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(KaiColor.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KaiSpacing.regular)
                    .padding(.bottom, 8)
                    
                    Divider().kaiDivider()
                    
                    // ── Message List ──
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleMessages) { msg in
                                mailMessageRow(msg)
                            }
                        }
                        .padding(KaiSpacing.regular)
                    }
                    .scrollIndicators(.automatic)
                }
            } else {
                KaiConnectCard(
                    title: "Mail",
                    icon: "envelope",
                    explanation: "Kai OS reads senders, subjects and dates from your Apple Mail inbox. It can't send or change anything, and nothing leaves this Mac.",
                    state: appState.mailState,
                    connect: appState.connectMail
                )
            }
        }
        .onAppear {
            if appState.mailConnected { appState.refreshMail() }
        }
    }
    
    // ── Message Row ──
    private func mailMessageRow(_ msg: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // ── Unread dot ──
                if !msg.isRead {
                    Circle().fill(KaiColor.primary).frame(width: 8, height: 8)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.from).font(KaiFont.bodyStrong)
                        .lineLimit(1)
                    
                    Text(msg.subject)
                        .font(KaiFont.caption)
                        .foregroundStyle(msg.isRead ? KaiColor.textTertiary : KaiColor.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                // ── Date & Star ──
                HStack(spacing: 6) {
                    Text(msg.date, style: .date)
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                    
                    if msg.starred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(KaiColor.warning)
                            .font(KaiFont.caption2Strong)
                    }
                }
            }
            .padding(KaiSpacing.regular)
            .background(
                RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                    .fill(msg.isRead ? Color.clear : KaiColor.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                            .stroke(msg.isRead ? Color.clear : KaiColor.primary.opacity(0.15), lineWidth: 0.5)
                    )
            )
        }
    }
}
