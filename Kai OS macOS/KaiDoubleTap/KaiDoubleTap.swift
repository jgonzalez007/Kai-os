//
//  KaiDoubleTap.swift
//  Kai OS macOS
//
//  Double tap the talk key to draft a reply to the email in front of you. In Mail it reads
//  the selected message. Anywhere else it reads the email from a screenshot. Nothing is sent:
//  the user edits the draft, then opens it as a Mail reply or copies it.
//

import AppKit
import KaiActions
import KaiCapture
import KaiLocalAI
import KaiLocalData

enum KaiReplyContext: Equatable {
    case mail(reference: KaiMailMessageReference, source: KaiEmailDraftSource)
    case screen(jpeg: Data)
}

/// Abstracted so the flow can be tested without Mail or screen permissions.
@MainActor
protocol KaiReplyContextProviding {
    func currentContext() async throws -> KaiReplyContext
}

@MainActor
struct KaiSystemReplyContextProvider: KaiReplyContextProviding {
    let appState: AppState

    func currentContext() async throws -> KaiReplyContext {
        if appState.frontmostBundleIdentifier == "com.apple.mail" {
            guard let email = try await KaiMailSelection.selectedEmail() else {
                throw KaiActionError.invalid("Select a message in Mail, then double tap again.")
            }
            return .mail(reference: email.reference, source: email.source)
        }
        guard appState.selectedModelSupportsVision else {
            throw KaiActionError.invalid("\(appState.selectedModel) can't read images. Open the email in Apple Mail, or choose a model with vision.")
        }
        guard KaiScreenGrabber.hasPermission else {
            KaiScreenGrabber.requestPermission()
            throw KaiScreenCaptureError.needsPermission
        }
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let display = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let jpeg = try await KaiScreenGrabber.capture(displayID: display, excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        return .screen(jpeg: jpeg)
    }
}

@MainActor
final class KaiDoubleTapController: ObservableObject {
    enum Phase: Equatable {
        case idle, reading, drafting, ready
        case failed(String)
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var context: KaiReplyContext?
    @Published var draft = ""
    @Published var instruction = ""
    /// The result of opening the current draft in Mail.
    @Published private(set) var openState: KaiActionCard.State?

    var contextProvider: any KaiReplyContextProviding
    var pasteboard = NSPasteboard.general

    private let appState: AppState
    private let ollama = KaiOllamaClient()
    private var task: Task<Void, Never>?
    private var emailCheckPassed = false
    private var closeTask: Task<Void, Never>?

    /// Called shortly after a reply opens in Mail, so the panel clears the way to its window.
    var onReplyOpened: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        contextProvider = KaiSystemReplyContextProvider(appState: appState)
    }

    var canOpenInMail: Bool {
        guard phase == .ready, case .mail = context, !trimmedDraft.isEmpty else { return false }
        switch openState {
        case .none, .failed: return true
        default: return false
        }
    }

    var canCopy: Bool { phase == .ready && !trimmedDraft.isEmpty }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start() {
        cancel()
        phase = .reading
        task = Task {
            do {
                let context = try await contextProvider.currentContext()
                guard !Task.isCancelled else { return }
                self.context = context
                await generate(from: context, previousDraft: nil)
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }

    /// Redrafts with the current instruction, revising the current draft when there's one.
    func regenerate() {
        guard let context, phase != .reading else { return }
        let previous = instruction.isEmpty ? nil : trimmedDraft
        task?.cancel()
        // Set before the task starts, so nothing can edit or open the old draft in between.
        phase = .drafting
        task = Task { await generate(from: context, previousDraft: previous) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        closeTask?.cancel()
        closeTask = nil
        emailCheckPassed = false
        phase = .idle
        context = nil
        draft = ""
        instruction = ""
        openState = nil
    }

    private func generate(from context: KaiReplyContext, previousDraft: String?) async {
        phase = .drafting
        openState = nil
        draft = ""
        let messages: [KaiOllamaMessage]
        switch context {
        case .mail(_, let source):
            messages = KaiReplyPrompt.messages(source: source, instruction: instruction, previousDraft: previousDraft)
        case .screen(let jpeg):
            messages = KaiReplyPrompt.messages(screenshot: jpeg, instruction: instruction, previousDraft: previousDraft)
        }
        do {
            if !appState.chatModels.contains(appState.selectedModel) { try await appState.refreshChatModels() }
            guard !appState.selectedModel.isEmpty else { throw KaiOllamaError.noChatModel }
            // Only a fresh screenshot needs checking; a redraft already passed.
            if case .screen(let jpeg) = context, previousDraft == nil, !emailCheckPassed {
                let answer = try await completeText(messages: KaiReplyPrompt.emailCheckMessages(screenshot: jpeg), temperature: 0)
                if Task.isCancelled { return }
                if KaiReplyPrompt.checkSaysNoEmail(answer) {
                    phase = .failed("I can't see an email on this screen. Open one and double tap again.")
                    return
                }
                emailCheckPassed = true
            }
            var text = ""
            // No tools are offered here: drafting from an untrusted email can't trigger anything.
            for try await event in ollama.streamChat(model: appState.selectedModel, messages: messages, tools: []) {
                if Task.isCancelled { return }
                guard case .text(let delta) = event else { continue }
                text += delta
                draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if Task.isCancelled { return }
            if draft.isEmpty {
                phase = .failed("The model returned an empty draft. Try again.")
            } else {
                phase = .ready
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    private func completeText(messages: [KaiOllamaMessage], temperature: Double) async throws -> String {
        var text = ""
        for try await event in ollama.streamChat(model: appState.selectedModel, messages: messages, tools: [], temperature: temperature) {
            if case .text(let delta) = event { text += delta }
        }
        return text
    }

    /// Runs only from the user's click on the button beside the text they've just read.
    func openInMail() {
        guard canOpenInMail, case .mail(let reference, let source) = context else { return }
        var card = KaiActionCard(action: .mailReply(
            reference: reference,
            recipient: source.sender,
            subject: source.subject,
            body: KaiMailReplyBody.compose(draft: trimmedDraft, source: source)
        ))
        _ = card.approve()
        openState = .running
        let log = appState.actionLog
        let executor = appState.actionExecutor
        do {
            // An action that can't be recorded doesn't run.
            try log.record(event: "approved", card: card, detail: nil)
        } catch {
            openState = .failed("The action log couldn't be written, so nothing was done.")
            return
        }
        Task {
            do {
                let detail = try await executor.perform(card.action)
                card.finish(.succeeded(detail))
                try? log.record(event: "succeeded", card: card, detail: detail)
                openState = .succeeded(detail)
                closeTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else { return }
                    self?.onReplyOpened?()
                }
            } catch {
                card.finish(.failed(error.localizedDescription))
                try? log.record(event: "failed", card: card, detail: error.localizedDescription)
                openState = .failed(error.localizedDescription)
            }
        }
    }

    func copyDraft() {
        guard canCopy else { return }
        pasteboard.clearContents()
        pasteboard.setString(trimmedDraft, forType: .string)
    }
}
