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
    /// A saved prompt's name when one was run, shown instead of "Proofread".
    @Published private(set) var titleOverride: String?
    /// What the suggestion changed, change by change, and the ones the person chose to skip.
    @Published private(set) var diff: KaiTextDiff?
    @Published private(set) var skipped: Set<Int> = []
    @Published var reviewing = false

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

    var title: String { titleOverride ?? task.title }

    /// The suggestion with the skipped changes left as the person wrote them.
    var composedText: String {
        guard let diff else { return text }
        return diff.text(accepting: Set(0..<diff.changeCount).subtracting(skipped))
    }

    var acceptedCount: Int { (diff?.changeCount ?? 0) - skipped.count }

    func toggleChange(_ index: Int) {
        if skipped.contains(index) { skipped.remove(index) } else { skipped.insert(index) }
    }

    private func updateDiff() {
        skipped = []
        diff = replaceState == .unavailable || original.isEmpty ? nil : KaiTextDiff(original: original, suggestion: text)
    }

    /// Runs a saved prompt on the text the person selected. There is no screen fallback: it needs the text.
    func runPrompt(_ prompt: KaiQuickPrompt, appState: AppState) {
        begin(.proofread, appState: appState, prompt: prompt)
    }

    func run(_ task: KaiScreenTask, appState: AppState) { begin(task, appState: appState, prompt: nil) }

    private func begin(_ task: KaiScreenTask, appState: AppState, prompt: KaiQuickPrompt?) {
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
        titleOverride = prompt?.name
        diff = nil; skipped = []; reviewing = false
        // Taken now, while the app the user was in is still in front.
        context = Self.currentContext(appState: appState, task: task)
        focused = nil
        running = Task {
            // A menu may have just closed: give the app you were in a moment to take the keyboard back.
            if prompt != nil { try? await Task.sleep(for: .milliseconds(180)) }
            // Read what the person is writing first, while their app still has the keyboard: the field's text,
            // or the text they selected. Kai's card takes the keyboard when it opens.
            if task == .proofread, let found = await KaiFocusedText.capture() {
                focused = found
                original = found.original
                replaceState = .ready
            }
            if Task.isCancelled { return }
            showPanel()
            // Let the bar finish closing so the cursor, not Kai, is what is on the screen.
            KaiNotchWindowController.shared.collapse()
            if let prompt {
                guard let focused else {
                    phase = .failed("Select the text you want to rewrite first (or click into it), then choose “\(prompt.name)” again. Accessibility has to be on for Kai OS.")
                    return
                }
                await proofreadField(focused, appState: appState, prompt: prompt)
            } else {
                await perform(task, appState: appState)
            }
        }
    }

    func close() {
        running?.cancel()
        stopSpeaking()
        panel?.orderOut(nil)
    }

    /// What Kai knows about this moment: the app and window, who the user is, and their own preferences.
    private static func currentContext(appState: AppState, task: KaiScreenTask) -> KaiScreenTask.Context {
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
                                     preferences: KaiInstructions.promptSection(KaiInstructions.stored()),
                                     writing: KaiNoAISlop.promptSection(for: task == .proofread ? .proofread : .summaries))
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
                // Finding slop doesn't change the suggestion: the findings go under it.
                let reportOnly = refinement == .detectSlop
                if reportOnly { notes = "" }
                for try await event in KaiOllamaClient().stream(model: model, messages: messages, tools: [], temperature: reportOnly ? 0.1 : 0.3) {
                    try Task.checkCancellation()
                    guard case .text(let delta) = event else { continue }
                    answer += delta
                    if reportOnly { notes = KaiScreenTask.cleaned(answer) } else { text = KaiScreenTask.cleaned(answer); notes = "" }
                }
                if !reportOnly, text.isEmpty { text = previous }
                if !reportOnly { updateDiff() }
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
    private func proofreadField(_ field: KaiFocusedText, appState: AppState, prompt: KaiQuickPrompt? = nil) async {
        guard let model = KaiScreenTask.localModel(selected: appState.selectedModel, available: appState.chatModels) else {
            phase = .failed("Proofread uses a model on this Mac, so your text never goes to the cloud. Start Ollama and download a model first (the Health page can help).")
            return
        }
        self.model = model
        let messages = prompt.map { KaiScreenTask.quickPromptMessages(original: field.original, prompt: $0, context: context) }
            ?? KaiScreenTask.proofreadTextMessages(original: field.original, isSelection: field.isSelection, context: context)
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
            updateDiff()
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Whether the suggestion is worth replacing the original with.
    var canReplace: Bool {
        guard phase == .done, !isRefining, replaceState == .ready || { if case .failed = replaceState { return true }; return false }() else { return false }
        return KaiScreenTask.isChange(original: original, suggestion: composedText)
    }

    /// The user approved the suggestion: it goes where the original was. Logged like any other action Kai takes.
    func replaceOriginal() {
        guard canReplace, let focused, let appState else { return }
        let composed = composedText
        let finalText = focused.isSelection ? composed : KaiScreenTask.matchingEdges(of: focused.original, composed)
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
        if task == .proofread, titleOverride == nil {
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
                Text(controller.title).font(.system(size: 19, weight: .semibold))
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
                 ? (controller.task == .proofread
                    ? "Read from your screen on this Mac. To replace your text from here, select it (or click into it) first, then press Proofread."
                    : "Read from your screen on this Mac. Nothing was sent anywhere.")
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

    /// Every change on its own: tick the ones to keep, untick the ones to skip.
    private func reviewList(_ diff: KaiTextDiff) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tick each change you want. What you leave unticked stays as you wrote it.").font(.caption).foregroundStyle(.white.opacity(0.6))
            ForEach(Array(diff.pieces.enumerated()), id: \.offset) { position, piece in
                if case .change(let index, let old, let new) = piece {
                    let on = !controller.skipped.contains(index)
                    Button { controller.toggleChange(index) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? KaiColor.cyan : Color.white.opacity(0.5)).font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 3) {
                                if position > 0, case .same(let before) = diff.pieces[position - 1] {
                                    Text("…" + before.split(separator: " ").suffix(5).joined(separator: " ")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                }
                                if !old.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(old.trimmingCharacters(in: .whitespacesAndNewlines)).strikethrough().foregroundStyle(Color.red.opacity(0.85))
                                }
                                if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Text(new.trimmingCharacters(in: .whitespacesAndNewlines)).foregroundStyle(Color.green.opacity(0.95))
                                }
                            }
                            .font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(on ? 0.08 : 0.03)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                    if let diff = controller.diff, diff.changeCount > 1 {
                        Button { controller.reviewing.toggle() } label: {
                            Label(controller.reviewing ? "Back" : "Review \(diff.changeCount) changes", systemImage: controller.reviewing ? "chevron.left" : "checklist")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: controller.replaceOriginal) {
                        Label(controller.diff.map { $0.changeCount > 1 && controller.acceptedCount < $0.changeCount ? "Replace with \(controller.acceptedCount) of \($0.changeCount) changes" : "Replace my text" } ?? "Replace my text",
                              systemImage: "arrow.triangle.2.circlepath")
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
                        if controller.reviewing, let diff = controller.diff, diff.changeCount > 0 {
                            reviewList(diff)
                        } else {
                        Text(rendered)
                            .font(.system(size: 18))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(controller.isRefining ? 0.7 : 1)
                        }
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
