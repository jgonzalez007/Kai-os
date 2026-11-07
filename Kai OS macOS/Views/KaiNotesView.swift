//
//  KaiNotesView.swift
//  Kai OS macOS
//
//  Modern notes view — card-style notes, smart search
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiNotesView: View {
    @EnvironmentObject var appState: AppState
    
    private var query: String { appState.notesQuery }
    
    private var visibleNotes: [NoteItem] {
        guard !query.isEmpty else { return appState.notes }
        return appState.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }
    
    var body: some View {
        Group {
            if appState.notesConnected {
                VStack(spacing: 0) {
                    // ── Header ──
                    HStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(KaiFont.labelStrong)
                            .foregroundStyle(KaiColor.primary)
                        
                        Text("Notes").font(KaiFont.title3)
                        Spacer()
                        
                        if appState.notesState == .loading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: KaiColor.primary))
                                .scaleEffect(0.7)
                        }
                        
                        Button("Refresh") {
                            appState.refreshNotes()
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
                        
                        TextField("Search notes", text: $appState.notesQuery)
                            .textFieldStyle(.plain)
                            .kaiInput()
                        
                        if !appState.notesQuery.isEmpty {
                            Button {
                                appState.notesQuery = ""
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
                    
                    // ── Notes List ──
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleNotes) { note in
                                notesCard(note)
                            }
                        }
                        .padding(KaiSpacing.regular)
                    }
                    .scrollIndicators(.automatic)
                }
            } else {
                KaiConnectCard(
                    title: "Notes",
                    icon: "note.text",
                    explanation: "Kai OS reads your most recent Apple Notes. It can't change them, and nothing leaves this Mac.",
                    state: appState.notesState,
                    connect: appState.connectNotes
                )
            }
        }
        .onAppear {
            if appState.notesConnected { appState.refreshNotes() }
        }
    }
    
    // ── Note Card ──
    private func notesCard(_ note: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(note.title).font(KaiFont.bodyStrong)
                    .lineLimit(1)
                
                Spacer()
                
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(KaiColor.warning)
                        .font(KaiFont.caption2Strong)
                }
                
                Text(note.date, style: .date)
                    .font(KaiFont.caption2Strong)
                    .foregroundStyle(KaiColor.textTertiary)
            }
            
            Text(note.content)
                .font(KaiFont.caption)
                .foregroundStyle(KaiColor.textTertiary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(KaiSpacing.regular)
        .background(
            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                .fill(KaiColor.surfaceBg)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadius)
                        .stroke(KaiColor.border.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}
