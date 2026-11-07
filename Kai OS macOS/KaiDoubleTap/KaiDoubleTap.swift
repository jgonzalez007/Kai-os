//
//  KaiDoubleTap.swift
//  Kai OS macOS
//
//  Double tap the talk key to reply to the email in front of you. In Mail it reads the
//  selected message. Anywhere else it reads the email from a screenshot. The draft is then
//  written into the email itself: at the cursor if it's in a text area, or into a new Mail
//  reply. Nothing is ever sent, so the user reviews it there and sends it themselves.
//

import AppKit
import KaiShared
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

/// Where a finished draft goes, decided from where the user's cursor was when they double tapped.
enum KaiReplyDestination: Equatable {
    case cursor
    case mailReply
    /// Nowhere to write yet: the user clicks into a reply box and presses Write.
    case awaitingCursor
}

@MainActor
struct KaiSystemReplyContextProvider: KaiReplyContextProviding {
    let appState: AppState
    let cursorIsInTextArea: Bool

    func currentContext() async throws -> KaiReplyContext {
        if appState.frontmostBundleIdentifier == "com.apple.mail" {
            if let email = try await KaiMailSelection.selectedEmail() {
                return .mail(reference: email.reference, source: email.source)
            }
            // A compose window can hold a reply with no message selected behind it.
            guard cursorIsInTextArea else {
                throw KaiActionError.invalid("Select a message in Mail, then double tap again.")
            }
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

/// Replies to one known message, for a card that names it.
@MainActor
struct KaiReferencedMailProvider: KaiReplyContextProviding {
    let reference: KaiMailMessageReference

    func currentContext() async throws -> KaiReplyContext {
        guard let email = try await KaiMailSelection.email(at: reference) else {
            throw KaiActionError.invalid("That message is no longer in Mail.")
        }
        return .mail(reference: email.reference, source: email.source)
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

    @Published private(set) var destination = KaiReplyDestination.awaitingCursor
    /// Why this draft was held back instead of being written automatically.
    @Published private(set) var factWarning: String?
    #if DEBUG
    /// Used by the self-test in place of the model, to force a specific draft.
    var scriptedDrafts: [String] = []
    #endif

    /// Set by the self-test; the real provider is built per double tap from the cursor's state.
    var contextProviderOverride: (any KaiReplyContextProviding)?
    var inserter: any KaiTextInserting = KaiPasteInserter()
    var pasteboard = NSPasteboard.general

    private let appState: AppState
    private let ollama = KaiOllamaClient()
    private var task: Task<Void, Never>?
    private var emailCheckPassed = false
    private var writesAutomatically = true
    private var closeTask: Task<Void, Never>?

    /// Called shortly after the draft is written, so the panel clears the way to the email.
    var onReplyOpened: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
    }

    /// Called before writing at the cursor, so keyboard focus returns to the user's app.
    var onReleaseFocus: (() -> Void)?

    var canWrite: Bool {
        guard phase == .ready, !trimmedDraft.isEmpty else { return false }
        switch openState {
        case .none, .failed: return true
        default: return false
        }
    }

    var writeButtonTitle: String {
        if destination == .mailReply { return "Write in Mail Reply" }
        return "Write at Cursor"
    }

    var canCopy: Bool { phase == .ready && !trimmedDraft.isEmpty }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start(provider requested: (any KaiReplyContextProviding)? = nil) {
        cancel()
        phase = .reading
        // Read now, before the panel opens and takes keyboard focus.
        let focus = inserter.currentFocus()
        let provider = contextProviderOverride ?? requested ?? KaiSystemReplyContextProvider(appState: appState, cursorIsInTextArea: focus == .multiline)
        writesAutomatically = true
        task = Task {
            do {
                let context = try await provider.currentContext()
                guard !Task.isCancelled else { return }
                self.context = context
                if focus == .multiline {
                    destination = .cursor
                } else if case .mail = context {
                    destination = .mailReply
                } else {
                    destination = .awaitingCursor
                }
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
        writesAutomatically = false
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
        factWarning = nil
        destination = .awaitingCursor
        phase = .idle
        context = nil
        draft = ""
        instruction = ""
        openState = nil
    }

    private func generate(from context: KaiReplyContext, previousDraft: String?) async {
        phase = .drafting
        openState = nil
        factWarning = nil
        draft = ""
        let messages: [KaiOllamaMessage]
        switch context {
        case .mail(_, let source):
            messages = KaiReplyPrompt.messages(source: source, instruction: instruction, previousDraft: previousDraft, style: appState.writingStyle.activeStyle)
        case .screen(let jpeg):
            messages = KaiReplyPrompt.messages(screenshot: jpeg, instruction: instruction, previousDraft: previousDraft, style: appState.writingStyle.activeStyle)
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
            try await streamDraft(messages)
            if Task.isCancelled { return }
            if await !passesFactCheck(context: context, messages: messages) { writesAutomatically = false }
            if Task.isCancelled { return }
            draft = KaiReplyPrompt.removingPlaceholderSignature(draft)
            if draft.isEmpty {
                phase = .failed("The model returned an empty draft. Try again.")
            } else {
                phase = .ready
                // Typing an instruction means the user wants to steer, so the draft waits.
                if writesAutomatically && instruction.isEmpty && destination != .awaitingCursor { writeDraft() }
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    private func streamDraft(_ messages: [KaiOllamaMessage]) async throws {
        draft = ""
        #if DEBUG
        if !scriptedDrafts.isEmpty {
            draft = scriptedDrafts.removeFirst()
            return
        }
        #endif
        var text = ""
        // No tools are offered here: drafting from an untrusted email can't trigger anything.
        for try await event in ollama.stream(model: appState.selectedModel, messages: messages, tools: []) {
            if Task.isCancelled { return }
            guard case .text(let delta) = event else { continue }
            text += delta
            draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Redrafts once if the draft adds a day or time the email doesn't state. If it still does,
    /// the result is false, so it's held for the user with a warning instead of being written.
    /// A screenshot's text isn't available to compare, so that path can't be checked.
    private func passesFactCheck(context: KaiReplyContext, messages: [KaiOllamaMessage]) async -> Bool {
        guard case .mail(_, let source) = context else { return true }
        let sources = [source.subject, source.body, instruction]
        let added = KaiReplyFactCheck.addedTimeWords(draft: draft, sources: sources)
        guard !added.isEmpty else { return true }
        let retry = messages + [
            KaiOllamaMessage(role: "assistant", content: draft),
            KaiOllamaMessage(role: "user", content: KaiReplyFactCheck.correction(for: added)),
        ]
        let original = draft
        do {
            try await streamDraft(retry)
        } catch {
            draft = original
        }
        let remaining = KaiReplyFactCheck.addedTimeWords(draft: draft, sources: sources)
        guard !remaining.isEmpty else { return true }
        factWarning = "This draft mentions \(remaining.joined(separator: " and ")), which the email doesn't. Check it before writing it."
        return false
    }

    private func completeText(messages: [KaiOllamaMessage], temperature: Double) async throws -> String {
        var text = ""
        for try await event in ollama.stream(model: appState.selectedModel, messages: messages, tools: [], temperature: temperature) {
            if case .text(let delta) = event { text += delta }
        }
        return text
    }

    /// Writes the draft into the email. It stays unsent there for the user to review.
    func writeDraft() {
        guard canWrite else { return }
        if destination == .mailReply, case .mail(let reference, let source) = context {
            writeMailReply(reference: reference, source: source)
        } else {
            writeAtCursor()
        }
    }

    private func writeAtCursor() {
        let text = trimmedDraft
        guard inserter.isAvailable else {
            openState = .failed(KaiTextInsertError.notAllowed.localizedDescription)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        var card = KaiActionCard(action: .insertText(app: frontmost?.localizedName ?? "Unknown", text: text))
        _ = card.approve()
        openState = .running
        guard record("approved", card: card) else { return }
        onReleaseFocus?()
        Task {
            // Gives the window server time to return keyboard focus before pasting.
            try? await Task.sleep(for: .milliseconds(200))
            do {
                try await inserter.insert(text)
                finishWrite(&card, .succeeded("Written into your email. Review it and send it yourself."))
            } catch {
                finishWrite(&card, .failed(error.localizedDescription))
            }
        }
    }

    /// With Accessibility, Mail composes the reply and quotes the original itself, and the
    /// draft is pasted above that. Without it, the script fills in the whole message.
    private func writeMailReply(reference: KaiMailMessageReference, source: KaiEmailDraftSource) {
        let text = trimmedDraft
        let pastes = inserter.isAvailable
        var card = KaiActionCard(action: .mailReply(
            reference: reference,
            recipient: source.sender,
            subject: source.subject,
            body: pastes ? "" : KaiMailReplyBody.compose(draft: text, source: source)
        ))
        _ = card.approve()
        openState = .running
        guard record("approved", card: card) else { return }
        let executor = appState.actionExecutor
        onReleaseFocus?()
        Task {
            do {
                let detail = try await executor.perform(card.action)
                if pastes {
                    // Mail needs a moment to open the reply and put the cursor in its body.
                    try? await Task.sleep(for: .milliseconds(900))
                    try await inserter.insert(text)
                    try? appState.actionLog.record(event: "pasted", card: card, detail: text)
                }
                finishWrite(&card, .succeeded(detail))
            } catch {
                finishWrite(&card, .failed(error.localizedDescription))
            }
        }
    }

    /// An action that can't be recorded doesn't run.
    private func record(_ event: String, card: KaiActionCard) -> Bool {
        do {
            try appState.actionLog.record(event: event, card: card, detail: nil)
            return true
        } catch {
            openState = .failed("The action log couldn't be written, so nothing was done.")
            return false
        }
    }

    private func finishWrite(_ card: inout KaiActionCard, _ outcome: KaiActionCard.State) {
        card.finish(outcome)
        switch outcome {
        case .succeeded(let detail):
            try? appState.actionLog.record(event: "succeeded", card: card, detail: detail)
            openState = outcome
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
                self?.onReplyOpened?()
            }
        case .failed(let detail):
            try? appState.actionLog.record(event: "failed", card: card, detail: detail)
            openState = outcome
        case .pending, .running, .declined:
            break
        }
    }

    func copyDraft() {
        guard canCopy else { return }
        pasteboard.clearContents()
        pasteboard.setString(trimmedDraft, forType: .string)
    }
}
