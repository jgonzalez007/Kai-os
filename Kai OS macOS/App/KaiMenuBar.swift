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

struct KaiMenuBarContent: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var desk = KaiDeskController.shared
    @ObservedObject private var updates = KaiUpdateController.shared
    @ObservedObject private var status = KaiStatusModel.shared

    var body: some View {
        let summary = status.summary(appState: appState, desk: desk, updates: updates)
        Text("Kai OS · \(summary.title)")
        Divider()
        ForEach(summary.lines, id: \.self) { Text($0) }
        Divider()
        Button("Ask Kai") { KaiNotchWindowController.shared.expand() }
        if summary.aiOffline && KaiOllamaSetup.isInstalled() {
            Button("Start Ollama") { startOllama() }
        }
        if let update = updates.available {
            Button("Update to \(update.version.description)…") { updates.openReleasePage() }
        }
        Divider()
        Button("Open Kai OS") { KaiNotchWindowController.shared.openMainWindow() }
        Button("Preferences…") {
            appState.activeSidebar = "Settings"
            KaiNotchWindowController.shared.openMainWindow()
        }
        Divider()
        Button("Quit Kai OS") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
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
