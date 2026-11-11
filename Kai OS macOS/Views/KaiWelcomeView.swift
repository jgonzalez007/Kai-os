//
//  KaiWelcomeView.swift
//  Kai OS macOS
//
//  The first-run guide: what Kai is, get a brain (Ollama and a model, or a cloud key), allow what
//  Kai needs, and start. Every step can be skipped and the guide can be reopened from the sidebar.
//

import AppKit
import KaiCapture
import KaiLocalAI
import KaiShared
import SwiftUI

@MainActor
final class KaiWelcomeModel: ObservableObject {
    @Published private(set) var ollama = KaiOllamaSetup.State.notInstalled
    @Published private(set) var pullProgress: KaiPullProgress?
    @Published private(set) var pullError: String?
    @Published private(set) var isPulling = false
    private var pullTask: Task<Void, Never>?

    func refresh(appState: AppState) async {
        let models = try? await KaiOllamaClient().listModels().map(\.name)
        let state = KaiOllamaSetup.evaluate(appInstalled: KaiOllamaSetup.isInstalled(), models: models)
        if state != ollama {
            ollama = state
            if case .ready = state { try? await appState.refreshChatModels() }
        }
    }

    func startOllama() {
        for path in KaiOllamaSetup.appPaths() where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
    }

    func downloadOllama() { NSWorkspace.shared.open(KaiOllamaSetup.downloadPage) }

    func pull(appState: AppState, model: String = KaiOllamaSetup.recommendedModel) {
        guard !isPulling, KaiOllamaSetup.isValidModelName(model) else { return }
        isPulling = true
        pullError = nil
        pullProgress = nil
        pullTask = Task {
            do {
                for try await progress in KaiOllamaClient().pull(model: model) { pullProgress = progress }
                await refresh(appState: appState)
            } catch is CancellationError {
            } catch {
                pullError = error.localizedDescription
            }
            isPulling = false
        }
    }

    func cancelPull() {
        pullTask?.cancel()
        isPulling = false
    }
}

struct KaiWelcomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var model = KaiWelcomeModel()
    @ObservedObject private var permissions = KaiPermissionsModel.shared
    @State private var step = 0

    private let titles = ["Welcome", "Choose your AI", "Allow what Kai needs", "You're set"]
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(titles[step]).font(.largeTitle).fontWeight(.bold)
                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .task { await model.refresh(appState: appState); await permissions.refresh() }
        .onReceive(refreshTimer) { _ in
            Task { await model.refresh(appState: appState); await permissions.refresh() }
        }
    }

    // MARK: Frame

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<titles.count, id: \.self) { i in
                Capsule().fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if step > 0 { Button("Back") { step -= 1 } }
            Spacer()
            if step < titles.count - 1 {
                if step > 0 { Button("Skip for now") { step += 1 } }
                Button("Continue") { step += 1 }.kaiProminent().keyboardShortcut(.defaultAction)
            } else {
                Button("Start using Kai") {
                    KaiPermissionsModel.markOnboarded()
                    appState.activeSidebar = "Chat"
                }
                .kaiProminent().keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: brain
        case 2: allow
        default: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kai is a personal AI that lives in your Mac's notch. This takes about two minutes.")
                .font(.title3).foregroundStyle(.secondary)
            bullet("lock.shield", "Private by default", "Chat runs on your Mac through a local model. Nothing is sent anywhere unless you add a ChatGPT or Claude key.")
            bullet("hand.raised", "You approve every action", "Kai can suggest a calendar event or an email draft. Nothing is created or sent until you press Approve.")
            bullet("arrow.up.left.and.arrow.down.right", "Always one click away", "Click the notch, or hold the talk key, from any app.")
        }
    }

    @ViewBuilder
    private var brain: some View {
        Text("Kai needs an AI to think with. The free option runs entirely on your Mac.").foregroundStyle(.secondary)
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("On this Mac (free, private)", systemImage: "desktopcomputer").font(.headline)
                ollamaStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("ChatGPT or Claude (your own key)", systemImage: "cloud").font(.headline)
                Text("Faster on older Macs. Your messages go to that company. Add the key in Preferences → Cloud AI.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open Preferences") { appState.openPreferences(.ai) }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    @ViewBuilder
    private var ollamaStatus: some View {
        switch model.ollama {
        case .notInstalled:
            Text("Ollama runs the AI on your Mac. Download and install it, open it once, then come back here. Kai notices on its own.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Download Ollama") { model.downloadOllama() }.kaiProminent()
        case .notRunning:
            Text("Ollama is installed but not running.").font(.callout).foregroundStyle(.secondary)
            Button("Start Ollama") { model.startOllama() }.kaiProminent()
        case .noModel:
            Text("Ollama is running. It needs a model, a one-time download of several gigabytes.")
                .font(.callout).foregroundStyle(.secondary)
            if model.isPulling {
                if let fraction = model.pullProgress?.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(model.pullProgress?.detail ?? "Starting…").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") { model.cancelPull() }.controlSize(.small)
            } else {
                Button("Download \(KaiOllamaSetup.recommendedModel)") { model.pull(appState: appState) }
                    .kaiProminent()
            }
            if let error = model.pullError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        case .ready(let models):
            Label("Ready. \(models.count) model\(models.count == 1 ? "" : "s") installed.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var allow: some View {
        Text("Kai asks macOS for these, one at a time. Allow what you want now; everything is optional and you can change it later in System Settings.")
            .foregroundStyle(.secondary)
        VStack(spacing: 0) {
            ForEach(KaiPermission.allCases) { permission in
                HStack(spacing: 10) {
                    Image(systemName: permission.iconName).foregroundStyle(.purple).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(permission.title)
                        Text(permission.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if permissions.statuses[permission] == .granted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 7)
                Divider()
            }
        }
        HStack {
            Button("Allow all") { permissions.requestAll() }
                .disabled(permissions.isRequestingAll || permissions.missingCount == 0)
            Text(permissions.missingCount == 0 ? "All set." : "\(permissions.missingCount) still to turn on.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.ollama {
            case .ready:
                Label("Your AI is ready.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            default:
                if KaiKeychain.hasApiKey(for: "openai") || KaiKeychain.hasApiKey(for: "anthropic") {
                    Label("Your cloud AI is ready.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("No AI is set up yet. Go back a step to add one.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            bullet("cursorarrow.click", "Click the notch", "Chat, your Shelf and your clipboard history are one click away from any app.")
            bullet("mic", "Hold the talk key", "Speak to Kai from anywhere. It listens only while you hold the key.")
            bullet("heart.text.square", "Something not working?", "Preferences → Health shows what is connected and how to fix what is not.")
            Text("You can reopen this guide any time from the sidebar.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.purple).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
