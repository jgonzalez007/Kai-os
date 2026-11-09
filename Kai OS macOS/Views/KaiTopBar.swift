//
//  KaiTopBar.swift
//  Kai OS macOS
//
//  The bar across the top of the main window: the Kai mark (home), a few places to go, and Preferences.
//  It replaces the old sidebar, so the window is mostly the thing you are doing.
//

import SwiftUI

struct KaiTopBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permissions = KaiPermissionsModel.shared
    @ObservedObject private var updates = KaiUpdateController.shared

    private var current: String { appState.activeSidebar }

    var body: some View {
        HStack(spacing: 6) {
            Button { appState.activeSidebar = "Chat" } label: {
                HStack(spacing: 8) {
                    KaiLogoMark(size: 26)
                    Text("Kai OS").font(.system(size: 14, weight: .semibold))
                }
                .padding(.trailing, 10)
            }
            .buttonStyle(.plain)
            .help("Home")

            Spacer()

            item("For You", "sun.max", tag: "ForYou", badge: appState.morningCards.activeCards.count)
            item("Computer tasks", "cursorarrow.motionlines", tag: "Sidekick")
            item("Knowledge", "point.3.connected.trianglepath.dotted", tag: "Knowledge")
            yourStuff

            if let update = updates.available {
                Button { updates.openReleasePage() } label: {
                    Label("Update \(update.version.description)", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KaiColor.cyan)
                }
                .buttonStyle(.plain)
                .help("Opens the release page. Kai OS does not install updates by itself.")
            }

            Button { appState.activeSidebar = "Settings" } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(alignment: .topTrailing) {
                        if permissions.missingCount > 0 {
                            Circle().fill(KaiColor.magenta).frame(width: 8, height: 8).offset(x: 1, y: -1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(permissions.missingCount > 0 ? "Preferences (\(permissions.missingCount) permissions still to turn on)" : "Preferences")
        }
        // The window's own buttons sit at the left edge.
        .padding(.leading, 84).padding(.trailing, 20)
        .frame(height: 52)
    }

    private func item(_ title: String, _ symbol: String, tag: String, badge: Int = 0) -> some View {
        Button { appState.activeSidebar = tag } label: { label(title, symbol, selected: current == tag, badge: badge) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String, _ symbol: String, selected: Bool, badge: Int = 0) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12))
            Text(title).font(.system(size: 13, weight: .medium))
            if badge > 0 {
                Text("\(badge)").font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
            }
        }
        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(selected ? Color.white.opacity(0.12) : .clear))
        .contentShape(Capsule())
    }

    /// Calendar, Mail and Notes share one menu, to keep the bar short.
    private var yourStuff: some View {
        Menu {
            Button { appState.activeSidebar = "Calendar" } label: { Label("Calendar (\(appState.calendarEvents.count))", systemImage: "calendar") }
            Button { appState.activeSidebar = "Mail" } label: { Label("Mail (\(appState.unreadCount) unread)", systemImage: "envelope") }
            Button { appState.activeSidebar = "Notes" } label: { Label("Notes (\(appState.notes.count))", systemImage: "note.text") }
        } label: {
            label("Your stuff", "square.stack", selected: ["Calendar", "Mail", "Notes"].contains(current))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.white)
        .fixedSize()
    }
}
