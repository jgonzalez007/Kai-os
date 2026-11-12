//
//  KaiClaudeChat.swift
//  Kai OS macOS
//
//  The chat on Claude. When Claude is the chosen chat model, a question goes to the person's own Claude Code
//  sign-in together with Kai's tools (only for the sources they switched on), so Claude can research across several
//  steps. It can also ask Sidekick to do something on the screen: the person sees the task and presses Start, and
//  what happens comes back to Claude as the tool's answer. The chat and Sidekick are one conversation.
//

import AppKit
import Foundation
import KaiAgent
import KaiShared

/// A computer task Claude asked for, shown in the chat until the person decides.
struct KaiScreenTaskCard: Equatable {
    enum State: Equatable {
        case asking
        case running
        case finished(String)
        case declined
    }

    var task: String
    var state = State.asking
}

extension AppState {
    static let screenTaskTool = KaiOllamaTool(
        name: "do_on_screen",
        description: "Do a task on the user's Mac screen with the mouse and keyboard: open an app, click, type, fill in a form. The user sees the task and must press Start first, and Kai's safety rules check every step. Returns what happened. Use it only when no reading tool can do the job.",
        parameters: [.init(name: "task", type: "string", description: "The task in plain words, with every detail needed (what to open, what to enter)", required: true)]
    )

    // MARK: The model list and its names

    /// "Claude Sonnet", for the picker. Local models keep their own names.
    static func modelLabel(_ model: String) -> String {
        guard KaiClaudeCode.isClaudeChoice(model) else { return model }
        let alias = KaiClaudeCode.alias(from: model)
        return (KaiClaudeCode.models.first { $0.alias == alias }?.title ?? "Claude") + " (research)"
    }

    /// The Claude choices for the chat, when Claude Code is installed on this Mac. The program is looked for at most every few minutes.
    func claudeChatModels() async -> [String] {
        if let cached = Self.claudeLookup, Date().timeIntervalSince(cached.at) < 300 {
            return cached.found ? KaiClaudeCode.models.map { KaiClaudeCode.modelPrefix + $0.alias } : []
        }
        let found = await KaiClaudeCode.locate(custom: UserDefaults.standard.string(forKey: KaiClaudeCode.pathKey)) != nil
        Self.claudeLookup = (found, Date())
        return found ? KaiClaudeCode.models.map { KaiClaudeCode.modelPrefix + $0.alias } : []
    }

    private static var claudeLookup: (found: Bool, at: Date)?

    // MARK: Keeping the conversation

    func scheduleConversationSave() {
        conversationSaveTask?.cancel()
        conversationSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveConversationNow()
        }
    }

    func saveConversationNow() {
        let stored = messages
            .filter { ($0.kind == .chat || $0.kind == .error) && !$0.text.isEmpty }
            .map { KaiStoredMessage(id: $0.id, text: $0.text, isUser: $0.isUser, timestamp: $0.timestamp, kind: $0.kind == .error ? "error" : "chat") }
        try? KaiConversationLog.standard.save(stored)
    }

    /// A line in the chat about a computer task Sidekick was given from its own page.
    func postSidekickTask(_ task: String) {
        messages.append(Message(text: "Sidekick task: " + task, isUser: true))
    }

    func postSidekickResult(_ text: String) {
        messages.append(Message(text: text))
    }

    // MARK: Answering with Claude

    func streamClaudeReply(replyID: String, history: [KaiOllamaMessage]) async {
        defer {
            if activeReplyID == replyID {
                activeReplyID = nil
                isProcessing = false
            }
            updateMessage(id: replyID) { $0.status = nil }
        }
        do {
            guard KaiResearch.hasConsent() else {
                throw ClaudeChatProblem("Chat on Claude sends your questions, and whatever the tools find in the sources you turn on, to Anthropic. Turn on “I understand” under Sidekick → Settings → Claude chat research, or pick a local model.")
            }
            guard let path = await KaiClaudeCode.locate(custom: UserDefaults.standard.string(forKey: KaiClaudeCode.pathKey)) else { throw KaiClaudeCodeError.notFound }
            let tools = KaiResearch.allowedTools(Self.tools(for: KaiMailAccess.current) + [Self.screenTaskTool])
            let sources = KaiResearchSource.allCases.map { "\($0.title): \(KaiResearch.isEnabled($0) ? "on" : "off")" }.joined(separator: ", ")
            let persona = history.first { $0.role == "system" }?.content ?? ""
            let system = persona + "\n\n" + KaiResearch.instructions + "\nSources the person has switched on for you: \(sources)."
            let prompt = KaiResearch.prompt(from: history)
            let alias = KaiClaudeCode.alias(from: selectedModel)

            var continuation: AsyncStream<KaiResearch.Event>.Continuation!
            let events = AsyncStream<KaiResearch.Event> { continuation = $0 }
            let feed = continuation!
            let consumer = Task { @MainActor in
                for await event in events {
                    switch event {
                    case .tool(let name):
                        // Whatever was written before a tool call is narration: the answer is what comes after the last one.
                        self.updateMessage(id: replyID) { $0.text = ""; $0.status = Self.toolStatus(for: name) }
                    case .text(let delta):
                        self.updateMessage(id: replyID) { $0.text += delta; $0.status = nil }
                    }
                }
            }
            let answer: String
            do {
                answer = try await KaiResearch.run(executable: path, alias: alias, system: system, prompt: prompt, tools: tools,
                                                   handler: { [weak self] call in await self?.runResearchTool(call) ?? "Kai isn't available." },
                                                   onEvent: { feed.yield($0) })
            } catch {
                feed.finish()
                await consumer.value
                throw error
            }
            feed.finish()
            await consumer.value
            updateMessage(id: replyID) { message in
                let clean = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { message.text = clean }
                if message.text.isEmpty { message.text = "Claude returned an empty reply."; message.kind = .error }
            }
        } catch is CancellationError {
            removeMessageIfEmpty(id: replyID)
        } catch {
            if Task.isCancelled { removeMessageIfEmpty(id: replyID); return }
            updateMessage(id: replyID) { $0.text = error.localizedDescription; $0.kind = .error }
        }
    }

    struct ClaudeChatProblem: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// One tool call from Claude. A source that is switched off is refused again here, in case the list was stale.
    func runResearchTool(_ call: KaiOllamaToolCall) async -> String {
        if call.name == Self.screenTaskTool.name {
            return await requestScreenTask(call.arguments["task"]?.stringValue ?? "")
        }
        if let source = KaiResearch.source(forTool: call.name) {
            guard KaiResearch.isEnabled(source) else {
                return "\(source.title) is switched off, so Kai did not read it. The person can turn it on under Settings → Sidekick → Claude chat research."
            }
        } else if !KaiResearch.cardTools.contains(call.name) {
            return "That tool isn't available here."
        }
        return await runTool(call)
    }

    // MARK: Computer tasks asked for in the chat

    /// Shows the task in the chat and waits. Nothing runs until the person presses Start, which only a person can do.
    func requestScreenTask(_ task: String) async -> String {
        let clean = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "No task was given." }
        guard !agent.isRunning else { return "Sidekick is already doing a task. Wait for it to finish." }
        var message = Message(kind: .screenTask)
        message.screenTask = KaiScreenTaskCard(task: String(clean.prefix(500)))
        if let activeReplyID, let index = messages.firstIndex(where: { $0.id == activeReplyID }) { messages.insert(message, at: index) } else { messages.append(message) }
        let id = message.id
        let start = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in screenTaskDecisions[id] = continuation }
        guard start else {
            setScreenTask(id) { $0.state = .declined }
            return "The person did not start the task, so nothing was done."
        }
        setScreenTask(id) { $0.state = .running }
        let result = await agent.runForChat(task: String(clean.prefix(500)), appState: self)
        setScreenTask(id) { $0.state = .finished(result) }
        return result
    }

    /// Only the card's Start and Not now buttons call this.
    func decideScreenTask(messageID: String, start: Bool) {
        screenTaskDecisions.removeValue(forKey: messageID)?.resume(returning: start)
    }

    func cancelPendingScreenTasks() {
        for (id, continuation) in screenTaskDecisions {
            setScreenTask(id) { $0.state = .declined }
            continuation.resume(returning: false)
        }
        screenTaskDecisions = [:]
    }

    private func setScreenTask(_ id: String, _ change: (inout KaiScreenTaskCard) -> Void) {
        updateMessage(id: id) { message in
            guard var card = message.screenTask else { return }
            change(&card)
            message.screenTask = card
        }
    }
}
