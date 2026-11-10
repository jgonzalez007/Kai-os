//
//  KaiResultCard.swift
//  Kai OS macOS
//
//  Summarize and Proofread from the notch bar: Kai looks at what is showing on the screen (one still,
//  taken when the chip is pressed, leaving out Kai's own windows) with the local vision model, and
//  answers in a black card under the notch. The screenshot never leaves this Mac.
//

import AppKit
import AVFoundation
import KaiActions
import KaiCapture
import KaiKnowledge
import KaiLocalAI
import KaiShared
import SwiftUI

@MainActor
final class KaiScreenTaskController: ObservableObject {
    static let shared = KaiScreenTaskController()

    enum Phase: Equatable {
        case working
        case done
        case failed(String)
    }

    @Published private(set) var task = KaiScreenTask.summarize
    @Published private(set) var phase = Phase.working
    @Published private(set) var text = ""
    @Published private(set) var isSpeaking = false
    /// What changed (proofread), as bullets and a tip. Empty for a summary.
    @Published private(set) var notes = ""
    @Published private(set) var isRefining = false
    /// Proofread only: the text Kai read from the field, and where the suggestion can go once approved.
    @Published private(set) var original = ""
    @Published private(set) var replaceState = ReplaceState.unavailable

    enum ReplaceState: Equatable {
        /// Nothing was read from a text field, so the answer can be copied but not swapped in.
        case unavailable
        case ready
        case replacing
        case replaced
        case failed(String)
    }

    private var focused: KaiFocusedText?
    private weak var appState: AppState?
    private var context = KaiScreenTask.Context()
    private var model = ""

    private var panel: KaiResultPanel?
    private var running: Task<Void, Never>?
    private let speech = AVSpeechSynthesizer()

    func run(_ task: KaiScreenTask, appState: AppState) {
        running?.cancel()
        stopSpeaking()
        self.task = task
        phase = .working
        text = ""
        notes = ""
        isRefining = false
        self.appState = appState
        original = ""
        replaceState = .unavailable
        // Taken now, while the app the user was in is still in front.
        context = Self.currentContext(appState: appState)
        focused = task == .proofread ? KaiFocusedText.capture() : nil
        if let focused {
            original = focused.original
            replaceState = .ready
        }
        showPanel()
        // Let the bar finish closing so the cursor, not Kai, is what is on the screen.
        KaiNotchWindowController.shared.collapse()
        running = Task { await perform(task, appState: appState) }
    }

    func close() {
        running?.cancel()
        stopSpeaking()
        panel?.orderOut(nil)
    }

    /// What Kai knows about this moment: the app and window, who the user is, and their own preferences.
    private static func currentContext(appState: AppState) -> KaiScreenTask.Context {
        let own = Bundle.main.bundleIdentifier
        let app = NSWorkspace.shared.frontmostApplication
        let front = app?.bundleIdentifier == own ? nil : app
        var title: String?
        if let pid = front?.processIdentifier,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            title = windows.first { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                && !(($0[kCGWindowName as String] as? String) ?? "").isEmpty }?[kCGWindowName as String] as? String
        }
        return KaiScreenTask.Context(appName: front?.localizedName, windowTitle: title,
                                     profile: KaiProfilePrompt.promptSection(appState.profile),
                                     preferences: KaiInstructions.promptSection(KaiInstructions.stored()))
    }

    /// Reworks the answer (shorter, action items, a reply, another tone) without looking at the screen again.
    func refine(_ refinement: KaiScreenTask.Refinement) {
        guard phase == .done, !isRefining, !text.isEmpty, !model.isEmpty else { return }
        isRefining = true
        let previous = text
        let messages = task.refineMessages(previous: previous, refinement: refinement, context: context)
        let model = model
        running?.cancel()
        running = Task {
            defer { isRefining = false }
            do {
                var answer = ""
                for try await event in KaiOllamaClient().stream(model: model, messages: messages, tools: [], temperature: 0.3) {
                    try Task.checkCancellation()
                    guard case .text(let delta) = event else { continue }
                    answer += delta
                    text = KaiScreenTask.cleaned(answer)
                    notes = ""
                }
                if text.isEmpty { text = previous }
            } catch is CancellationError {
            } catch {
                text = previous
            }
        }
    }

    func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func toggleSpeaking() {
        if isSpeaking { stopSpeaking(); return }
        guard !text.isEmpty else { return }
        speech.speak(AVSpeechUtterance(string: text))
        isSpeaking = true
    }

    private func stopSpeaking() {
        speech.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func perform(_ task: KaiScreenTask, appState: AppState) async {
        if let focused {
            await proofreadField(focused, appState: appState)
            return
        }
        guard KaiScreenGrabber.hasPermission else {
            KaiScreenGrabber.requestPermission()
            phase = .failed(KaiScreenCaptureError.needsPermission.localizedDescription)
            return
        }
        guard let model = KaiScreenTask.localModel(selected: appState.selectedModel, available: appState.chatModels) else {
            phase = .failed("\(task.title) reads your screen with a model on this Mac, so it never sends a screenshot to the cloud. Start Ollama and download a model with vision first (the Health page can help).")
            return
        }
        self.model = model
        do {
            try await Task.sleep(for: .milliseconds(450))
            let screenshot = try await KaiScreenGrabber.capture(
                displayID: Self.displayUnderCursor(),
                excludingBundleIdentifier: Bundle.main.bundleIdentifier
            )
            var answer = ""
            for try await event in KaiOllamaClient().stream(model: model, messages: task.messages(screenshot: screenshot, context: context), tools: [], temperature: 0.2) {
                try Task.checkCancellation()
                guard case .text(let delta) = event else { continue }
                answer += delta
                apply(answer)
            }
            apply(answer)
            phase = text.isEmpty ? .failed("The model returned nothing. Try again.") : .done
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Proofreads the text read from the field the user is writing in. No screenshot, no Screen Recording.
    private func proofreadField(_ field: KaiFocusedText, appState: AppState) async {
        guard let model = KaiScreenTask.localModel(selected: appState.selectedModel, available: appState.chatModels) else {
            phase = .failed("Proofread uses a model on this Mac, so your text never goes to the cloud. Start Ollama and download a model first (the Health page can help).")
            return
        }
        self.model = model
        let messages = KaiScreenTask.proofreadTextMessages(original: field.original, isSelection: field.isSelection, context: context)
        do {
            var answer = ""
            for try await event in KaiOllamaClient().stream(model: model, messages: messages, tools: [], temperature: 0.2) {
                try Task.checkCancellation()
                guard case .text(let delta) = event else { continue }
                answer += delta
                apply(answer)
            }
            apply(answer)
            phase = text.isEmpty ? .failed("The model returned nothing. Try again.") : .done
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Whether the suggestion is worth replacing the original with.
    var canReplace: Bool {
        guard phase == .done, !isRefining, replaceState == .ready || { if case .failed = replaceState { return true }; return false }() else { return false }
        return KaiScreenTask.isChange(original: original, suggestion: text)
    }

    /// The user approved the suggestion: it goes where the original was. Logged like any other action Kai takes.
    func replaceOriginal() {
        guard canReplace, let focused, let appState else { return }
        let finalText = focused.isSelection ? text : KaiScreenTask.matchingEdges(of: focused.original, text)
        var card = KaiActionCard(action: .insertText(app: focused.appName, text: finalText))
        _ = card.approve()
        do { try appState.actionLog.record(event: "approved", card: card, detail: nil) } catch {
            replaceState = .failed("The action log couldn't be written, so nothing was replaced.")
            return
        }
        replaceState = .replacing
        Task {
            do {
                try await focused.replace(with: finalText)
                card.finish(.succeeded("Replaced your text in \(focused.appName)."))
                try? appState.actionLog.record(event: "succeeded", card: card, detail: "Replaced your text.")
                replaceState = .replaced
                try? await Task.sleep(for: .milliseconds(1400))
                if replaceState == .replaced { close() }
            } catch {
                card.finish(.failed(error.localizedDescription))
                try? appState.actionLog.record(event: "failed", card: card, detail: error.localizedDescription)
                replaceState = .failed(error.localizedDescription)
            }
        }
    }

    /// A proofread answer is the corrected text, then a line of dashes, then what changed.
    private func apply(_ answer: String) {
        let cleaned = KaiScreenTask.cleaned(answer)
        if task == .proofread {
            let split = KaiScreenTask.splitNotes(cleaned)
            text = split.text
            notes = split.notes
        } else {
            text = cleaned
        }
    }

    private static func displayUnderCursor() -> CGDirectDisplayID? {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: Window

    private func showPanel() {
        if panel == nil {
            let panel = KaiResultPanel(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.onCancel = { [weak self] in self?.close() }
            panel.contentView = NSHostingView(rootView: KaiResultCard(controller: self))
            self.panel = panel
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.frame {
            // Centered on the screen, a little above the middle, like the Summary card in Sentient.
            let width = min(660, frame.width - 80), height = min(500, frame.height - 160)
            panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - height / 2 + 40, width: width, height: height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}

final class KaiResultPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct KaiResultCard: View {
    @ObservedObject var controller: KaiScreenTaskController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(controller.task.title).font(.system(size: 19, weight: .semibold))
                if controller.phase == .done {
                    Button(action: controller.toggleSpeaking) {
                        Label(controller.isSpeaking ? "Stop" : "Read text", systemImage: controller.isSpeaking ? "stop.fill" : "doc.text")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !controller.text.isEmpty {
                    Button(action: controller.copy) {
                        Label("Copy", systemImage: "doc.on.doc").font(.callout)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: controller.close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider().overlay(Color.white.opacity(0.1))
            content
            Divider().overlay(Color.white.opacity(0.08))
            Text(controller.replaceState == .unavailable
                 ? "Read from your screen on this Mac. Nothing was sent anywhere."
                 : "Read on this Mac. Nothing is replaced until you press Replace.")
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.horizontal, 22).padding(.vertical, 9)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
    }

    /// Bold, italic and code from the model's answer; list markers become bullets.
    private var rendered: AttributedString {
        let text = KaiScreenTask.forDisplay(controller.text)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var renderedNotes: AttributedString {
        let text = KaiScreenTask.forDisplay(controller.notes)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    /// The suggestion replaces the original only when this button is pressed.
    private var approvalBar: some View {
        HStack(spacing: 10) {
            switch controller.replaceState {
            case .replaced:
                Label("Replaced in your text", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .replacing:
                ProgressView().controlSize(.small)
                Text("Replacing…").foregroundStyle(.secondary)
            default:
                if KaiScreenTask.isChange(original: controller.original, suggestion: controller.text) {
                    Button(action: controller.replaceOriginal) {
                        Label("Replace my text", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(KaiColor.liquidBlue))
                    }
                    .buttonStyle(.plain).disabled(!controller.canReplace)
                    Button("Keep mine", action: controller.close).buttonStyle(.plain)
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                } else {
                    Label("Nothing to change", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                if case .failed(let message) = controller.replaceState {
                    Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 22).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if controller.text.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(controller.task.workingText).foregroundStyle(.secondary)
                        }
                    } else {
                        if controller.replaceState != .unavailable {
                            Text("SUGGESTION").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(KaiColor.cyan)
                        }
                        Text(rendered)
                            .font(.system(size: 18))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(controller.isRefining ? 0.7 : 1)
                    }
                    if !controller.notes.isEmpty {
                        Divider().overlay(Color.white.opacity(0.12)).padding(.vertical, 4)
                        Text(renderedNotes)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if controller.replaceState != .unavailable, !controller.original.isEmpty, controller.phase == .done {
                        DisclosureGroup {
                            Text(controller.original)
                                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).lineSpacing(3)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        } label: {
                            Text("Your original").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(24)
            }
            if controller.phase == .done, controller.replaceState != .unavailable {
                Divider().overlay(Color.white.opacity(0.08))
                approvalBar
            }
            if controller.phase == .done {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 8) {
                    ForEach(KaiScreenTask.Refinement.available(for: controller.task), id: \.self) { refinement in
                        Button { controller.refine(refinement) } label: {
                            Text(refinement.title).font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain).disabled(controller.isRefining)
                    }
                    if controller.isRefining { ProgressView().controlSize(.small) }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.vertical, 10)
            }
        }
    }
}
