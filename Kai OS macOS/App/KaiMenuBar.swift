//
//  KaiMenuBar.swift
//  Kai OS macOS
//
//  Kai's item in the Mac's menu bar: an icon that follows Kai's state, and a menu with the
//  details and a few quick actions.
//

import AppKit
import KaiLocalAI
import KaiShared
import SwiftUI

struct KaiMenuBarLabel: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var desk = KaiDeskController.shared
    @ObservedObject private var updates = KaiUpdateController.shared
    @ObservedObject private var status = KaiStatusModel.shared

    var body: some View {
        let summary = status.summary(appState: appState, desk: desk, updates: updates)
        Image(systemName: summary.symbol)
            .help("Kai OS: \(summary.title)")
    }
}

/// The menu bar window: the notch manager from the asset package, with Kai's status and quick actions.
struct KaiMenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var desk = KaiDeskController.shared
    @ObservedObject private var updates = KaiUpdateController.shared
    @ObservedObject private var status = KaiStatusModel.shared
    @AppStorage(KaiNotchPreferences.enabledKey) private var notchEnabled = true
    @AppStorage(KaiNotchPreferences.glowKey) private var glow = 0.9
    @AppStorage(KaiNotchPreferences.peeksKey) private var alerts = false
    @State private var chosen = KaiStatsItem.stored()

    private var notch: KaiNotchWindowController { KaiNotchWindowController.shared }

    var body: some View {
        let summary = status.summary(appState: appState, desk: desk, updates: updates)
        VStack(spacing: 12) {
            header(summary)

            HStack(alignment: .top, spacing: 12) {
                card(KaiColor.cyan) {
                    HStack {
                        Text("Notch").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Toggle("", isOn: $notchEnabled).labelsHidden().toggleStyle(.switch).tint(KaiColor.cyan).scaleEffect(0.75)
                            .onChange(of: notchEnabled) { _, _ in notch.applyEnabledPreference() }
                    }
                    Divider().overlay(Color.white.opacity(0.1))
                    Text("Glow intensity").font(.system(size: 10)).foregroundStyle(.gray)
                    Slider(value: $glow, in: 0.2...1).tint(KaiColor.cyan)
                }
                card(KaiColor.magenta) {
                    Text("Stats bar").font(.system(size: 11, weight: .semibold))
                    Divider().overlay(Color.white.opacity(0.1))
                    HStack(spacing: 6) {
                        ForEach(KaiStatsItem.allCases, id: \.self) { item in
                            statButton(item)
                        }
                    }
                }
            }

            card(KaiColor.cyan) {
                Text("Quick actions").font(.system(size: 11, weight: .semibold))
                HStack(spacing: 8) {
                    action(notchEnabled ? "Hider" : "Show", notchEnabled ? "eye.slash" : "eye", KaiColor.cyan) {
                        if notchEnabled { notch.hideNotch() } else { notch.showNotch() }
                        notchEnabled = KaiNotchPreferences.isEnabled
                    }
                    action("Stats", "gauge.medium", KaiColor.magenta) { open(.stats) }
                    action("Shelf", "tray", KaiColor.magenta) { open(.shelf) }
                    action("Clipboard", "doc.on.clipboard", KaiColor.cyan) { open(.clipboard) }
                }
            }

            card(KaiColor.magenta) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notch alerts").font(.system(size: 11, weight: .semibold))
                        Text("Wings beside the notch while Kai works").font(.system(size: 10)).foregroundStyle(.gray)
                    }
                    Spacer()
                    Toggle("", isOn: $alerts).labelsHidden().toggleStyle(.switch).tint(KaiColor.magenta).scaleEffect(0.75)
                        .onChange(of: alerts) { _, _ in notch.preferencesChanged() }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(summary.lines, id: \.self) { Text($0).font(.system(size: 11)).foregroundStyle(KaiColor.textBase.opacity(0.8)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            footer(summary)
        }
        .padding(14)
        .frame(width: 380)
        .background(LinearGradient(colors: [KaiColor.windowBg, .black], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(KaiColor.textBase)
        .environment(\.colorScheme, .dark)
        .onAppear { chosen = KaiStatsItem.stored() }
    }

    // MARK: Pieces

    private func header(_ summary: KaiMenuStatus) -> some View {
        HStack(spacing: 10) {
            KaiLogoMark(size: 34, pulsing: summary.level == .working)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kai-os").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("Notch Manager · \(summary.title)").font(.system(size: 11, weight: .medium)).foregroundStyle(.gray)
            }
            Spacer()
        }
    }

    private func card<Content: View>(_ accent: Color, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kaiLiquidGlass(accent)
    }

    private func statButton(_ item: KaiStatsItem) -> some View {
        let active = chosen.contains(item)
        return Button {
            if active { chosen.remove(item) } else { chosen.insert(item) }
            KaiStatsItem.store(chosen)
        } label: {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .white : .gray)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(active ? KaiColor.cyan.opacity(0.3) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? KaiColor.cyan : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(item.title)
    }

    private func action(_ title: String, _ symbol: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func footer(_ summary: KaiMenuStatus) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                footerButton("Ask Kai", "text.bubble") { notch.expand(); closeMenu() }
                footerButton("Open Kai OS", "macwindow") { notch.openMainWindow(); closeMenu() }
                footerButton("Preferences", "gearshape") {
                    appState.activeSidebar = "Settings"
                    notch.openMainWindow()
                    closeMenu()
                }
            }
            HStack(spacing: 8) {
                if summary.aiOffline && KaiOllamaSetup.isInstalled() {
                    footerButton("Start Ollama", "play.circle") { startOllama() }
                }
                if let update = updates.available {
                    footerButton("Update \(update.version.description)", "arrow.down.circle") { updates.openReleasePage() }
                }
                footerButton("Quit", "power") { NSApp.terminate(nil) }
            }
        }
    }

    private func footerButton(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func open(_ tab: KaiDeskController.Tab) {
        desk.tab = tab
        notch.expand()
        closeMenu()
    }

    /// Closes the menu bar window after an action, so it does not sit over what was just opened.
    private func closeMenu() {
        NSApp.windows.filter { $0.className.contains("MenuBarExtra") }.forEach { $0.orderOut(nil) }
    }

    private func startOllama() {
        for path in KaiOllamaSetup.appPaths() where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            break
        }
        // Check again shortly after it has had time to start.
        Task {
            try? await Task.sleep(for: .seconds(6))
            await status.check(appState: appState)
        }
    }
}
