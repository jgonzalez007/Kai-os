//
//  KaiSidebarView.swift
//  Kai OS macOS
//
//  Sidebar navigation: dark, with rounded pill rows, grouped like Preferences.
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiSidebarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = KaiPermissionsModel.shared
    @ObservedObject private var updates = KaiUpdateController.shared

    let selection: Binding<String?>

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    header
                    group("Kai") {
                        row("Chat", "bubble.left.and.bubble.right", tag: "Chat")
                        row("For You", "sun.max", tag: "ForYou", badge: appState.morningCards.activeCards.count)
                        row("Calendar", "calendar", tag: "Calendar", badge: appState.calendarEvents.count)
                        row("Mail", "envelope", tag: "Mail", badge: appState.unreadCount)
                        row("Notes", "note.text", tag: "Notes", badge: appState.notes.count)
                    }
                    group("Context") { context }
                    if !appState.notes.isEmpty {
                        group("Recent notes") { recentNotes }
                    }
                    group("More") {
                        if let update = updates.available {
                            Button { updates.openReleasePage() } label: {
                                pill(selected: false) {
                                    Image(systemName: "arrow.down.circle.fill").frame(width: 20)
                                    Text("Update to \(update.version.description)")
                                    Spacer()
                                }
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Opens the release page. Kai OS does not install updates by itself.")
                        }
                        row("Setup guide", "wand.and.stars", tag: "Welcome")
                        row("Sidekick", "cursorarrow.motionlines", tag: "Sidekick")
                        row("Health", "heart.text.square", tag: "Health")
                        row("Permissions", "lock.shield", tag: "Permissions", badge: permissions.missingCount)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
            }
            Divider().overlay(Color.white.opacity(0.08))
            VStack(spacing: 2) {
                row("Preferences", "gearshape", tag: "Settings")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.35))
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 10) {
            KaiLogoMark(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kai OS").font(.system(size: 18, weight: .semibold))
                Text("Personal AI").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                .padding(.top, 16).padding(.bottom, 6).padding(.leading, 6)
            content()
        }
    }

    /// The shape every row shares.
    private func pill<Content: View>(selected: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? LinearGradient(colors: [KaiColor.cyan.opacity(0.18), KaiColor.violet.opacity(0.22)], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [.clear], startPoint: .leading, endPoint: .trailing)))
            .contentShape(Rectangle())
    }

    private func row(_ title: String, _ symbol: String, tag: String, badge: Int = 0) -> some View {
        Button { selection.wrappedValue = tag } label: {
            pill(selected: selection.wrappedValue == tag) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                Text(title)
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.caption).fontWeight(.medium)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var context: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoCard(label: "App", value: appState.frontmostApp,
                     symbol: AppCategory(rawValue: appState.appCategory)?.icon ?? "app", tint: KaiColor.primary)
            infoCard(label: "Mode", value: appState.appAwarenessMode, symbol: "sparkles", tint: KaiColor.secondary)
            if !appState.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick actions").font(.caption).foregroundStyle(.secondary)
                    ForEach(appState.suggestions, id: \.self) { suggestion in
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(KaiColor.primary)
                            Text(suggestion).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.top, 2)
            }
        }
    }

    private func infoCard(label: String, value: String, symbol: String, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).fontWeight(.medium).lineLimit(1)
            }
            Spacer()
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .kaiGlassSurface(radius: 16)
    }

    private var recentNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(appState.notes.prefix(3))) { note in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(note.title).font(.caption).fontWeight(.medium).lineLimit(1)
                        Spacer()
                        if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(KaiColor.warning) }
                    }
                    Text(note.content).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
            }
        }
    }
}
