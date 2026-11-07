//
//  KaiSidebarView.swift
//  Kai OS macOS
//
//  Sidebar navigation — modern, clean, with app-aware context
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiSidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = KaiPermissionsModel.shared
    
    let selection: Binding<String?>
    
    var body: some View {
        List(selection: selection) {
            // ── App Header ──
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "cpu.chip")
                        .font(.title2)
                        .foregroundStyle(KaiColor.primary)
                        .kaiGlow()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kai OS").font(KaiFont.title3)
                        Text("Personal AI").font(KaiFont.caption2Strong)
                            .foregroundStyle(KaiColor.textTertiary)
                    }
                }
                .kaiSidebarItem(active: false)
                .padding(.bottom, 4)
            }
            
            // ── Main Navigation ──
            Section {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
                    .tag("Chat")
                
                Label("For You", systemImage: "sun.max")
                    .badge(appState.morningCards.activeCards.count)
                    .tag("ForYou")
                
                Label("Calendar", systemImage: "calendar")
                    .badge(appState.calendarEvents.count)
                    .tag("Calendar")
                
                Label("Mail", systemImage: "envelope")
                    .badge(appState.unreadCount)
                    .tag("Mail")
                
                Label("Notes", systemImage: "note.text")
                    .badge(appState.notes.count)
                    .tag("Notes")
            }
            
            // ── Context Section ──
            Section {
                Text("Context").kaiSectionHeader()
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Text(appState.frontmostApp).font(KaiFont.bodyStrong)
                        }
                        
                        Spacer()
                        
                        Image(systemName: AppCategory(rawValue: appState.appCategory)?.icon ?? "app")
                            .foregroundStyle(KaiColor.primary)
                    }
                    .padding(8)
                    .background(KaiColor.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mode").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Text(appState.appAwarenessMode).font(KaiFont.bodyStrong)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "sparkles")
                            .foregroundStyle(KaiColor.secondary)
                    }
                    .padding(8)
                    .background(KaiColor.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    
                    if !appState.suggestions.isEmpty {
                        Divider().kaiDivider()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Quick Actions").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            
                            ForEach(appState.suggestions, id: \.self) { suggestion in
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .font(KaiFont.caption2Strong)
                                        .foregroundStyle(KaiColor.primary)
                                    Text(suggestion).font(KaiFont.caption2Strong)
                                        .foregroundStyle(KaiColor.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            
            // ── Recent Notes ──
            if !appState.notes.isEmpty {
                Section {
                    Text("Recent Notes").kaiSectionHeader()
                    
                    ForEach(Array(appState.notes.prefix(3))) { note in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(note.title).font(KaiFont.captionStrong)
                                    .foregroundStyle(KaiColor.textPrimary)
                                Spacer()
                                if note.pinned {
                                    Image(systemName: "pin.fill")
                                        .foregroundStyle(KaiColor.warning)
                                        .font(KaiFont.caption3)
                                }
                            }
                            Text(note.content)
                                .font(KaiFont.caption3)
                                .foregroundStyle(KaiColor.textTertiary)
                                .lineLimit(2)
                        }
                        .padding(6)
                        .background(Color.clear)
                    }
                }
            }
            
            // ── Bottom ──
            Section {
                Label("Sidekick", systemImage: "cursorarrow.motionlines")
                    .tag("Sidekick")

                Label("Health", systemImage: "heart.text.square")
                    .tag("Health")

                Label("Permissions", systemImage: "lock.shield")
                    .badge(permissions.missingCount)
                    .tag("Permissions")
                
                Label("Preferences", systemImage: "gearshape")
                    .tag("Settings")
            }
        }
        .listStyle(.sidebar)
    }
}
