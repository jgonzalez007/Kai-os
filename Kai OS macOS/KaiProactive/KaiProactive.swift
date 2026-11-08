//
//  KaiProactive.swift
//  Kai OS macOS
//
//  Builds the morning "For You" cards once a day while the app is running.
//

import AppKit
import KaiShared
import KaiSlack
import KaiActions
import KaiLocalAI
import KaiLocalData

/// Abstracted so the flow can be tested without the user's real calendar and mail.
@MainActor
protocol KaiBriefingInputProviding {
    var hasSources: Bool { get }
    func currentInput() async throws -> KaiBriefingInput
}

@MainActor
struct KaiSystemBriefingInputProvider: KaiBriefingInputProviding {
    let appState: AppState

    /// What the person chose under Night Shift. Mail is off until chosen, so a big mailbox isn't read by surprise.
    private var chosen: Set<KaiNightShiftSource> { appState.nightShift.sources }

    private var useCalendar: Bool { appState.calendarConnected && chosen.contains(.calendar) }
    private var useMail: Bool { appState.mailConnected && chosen.contains(.mail) }
    private var useSlack: Bool { appState.slackClient != nil && chosen.contains(.slack) }

    var hasSources: Bool { useCalendar || useMail || useSlack }

    func currentInput() async throws -> KaiBriefingInput {
        var events: [KaiBriefingEvent] = []
        if useCalendar {
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: start)) ?? start
            events = KaiCalendarSource.events(from: start, to: end).map { item in
                KaiBriefingEvent(title: item.title, start: item.start, minutes: Int(item.end.timeIntervalSince(item.start) / 60), location: item.location)
            }
        }
        let mail = useMail ? try await KaiMailBriefing.unreadMessages() : []
        // Slack is a bonus: if it fails, the cards are still made from the rest.
        var slack: [String] = []
        if useSlack, let client = appState.slackClient {
            let calendar = Calendar.current
            let since = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            if let documents = try? await KaiSlackIndexer.recentDocuments(client: client, includeDirectMessages: appState.slackIncludeDirectMessages, since: since, maxChannels: 15) {
                slack = documents.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }.prefix(12)
                    .map { "\($0.title)\n" + String($0.text.prefix(500)) }
            }
        }
        return KaiBriefingInput(events: events, mail: mail, slack: slack)
    }
}

@MainActor
final class KaiMorningCardsController: ObservableObject {
    private static let checkInterval: Duration = .seconds(15 * 60)

    @Published private(set) var cards: [KaiMorningCard] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    private(set) var lastRunDay: String?
    /// When the last automatic attempt failed. A manual refresh is never held back by this.
    private(set) var lastFailure: Date?

    /// These are replaced by the self-test, so it never touches real data.
    var inputProvider: any KaiBriefingInputProviding
    var store = KaiBriefingStore.standard

    private let appState: AppState
    private let ollama = KaiOllamaClient()
    private var schedule: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    var activeCards: [KaiMorningCard] { cards.filter(\.isActive) }
    var hasSources: Bool { inputProvider.hasSources }

    init(appState: AppState) {
        self.appState = appState
        inputProvider = KaiSystemBriefingInputProvider(appState: appState)
    }

    func start() {
        guard schedule == nil else { return }
        loadStoredCards()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.generateIfDue() }
        }
        schedule = Task { [weak self] in
            while !Task.isCancelled {
                self?.generateIfDue()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func loadStoredCards() {
        guard let stored = store.load(), stored.day == KaiBriefingSchedule.dayKey(for: Date()) else {
            cards = []
            lastRunDay = nil
            return
        }
        lastRunDay = stored.day
        cards = stored.cards.map(Self.recoveringInterruptedAction)
    }

    func generateIfDue(now: Date = Date()) {
        guard hasSources, !isGenerating, KaiBriefingSchedule.isDue(now: now, lastRunDay: lastRunDay, lastFailure: lastFailure) else { return }
        generate()
    }

    func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        Task {
            defer { isGenerating = false }
            do {
                let input = try await inputProvider.currentInput()
                let now = Date()
                let fresh = input.isEmpty ? [] : try await requestCards(input: input, now: now)
                for card in fresh {
                    if case .action(let actionCard) = card.kind {
                        try? appState.actionLog.record(event: "proposed", card: actionCard, detail: "morning card")
                    }
                }
                cards = fresh
                // A day is only marked done once it has worked, so a failure retries at the next check.
                lastRunDay = KaiBriefingSchedule.dayKey(for: now)
                lastFailure = nil
                persist()
            } catch {
                errorMessage = error.localizedDescription
                lastFailure = Date()
            }
        }
    }

    func dismiss(_ id: String) {
        update(id) { $0.dismiss() }
    }

    /// Only the card's Approve button calls this. No model output can reach it.
    func approve(_ id: String) {
        guard let card = cards.first(where: { $0.id == id }), case .action(var actionCard) = card.kind, actionCard.approve() else { return }
        update(id) { $0.kind = .action(actionCard) }
        guard (try? appState.actionLog.record(event: "approved", card: actionCard, detail: "morning card")) != nil else {
            actionCard.finish(.failed("The action log couldn't be written, so nothing was done."))
            update(id) { $0.kind = .action(actionCard) }
            return
        }
        let action = actionCard.action
        let executor = appState.actionExecutor
        Task {
            do {
                let detail = try await executor.perform(action)
                actionCard.finish(.succeeded(detail))
                try? appState.actionLog.record(event: "succeeded", card: actionCard, detail: detail)
            } catch {
                actionCard.finish(.failed(error.localizedDescription))
                try? appState.actionLog.record(event: "failed", card: actionCard, detail: error.localizedDescription)
            }
            update(id) { $0.kind = .action(actionCard) }
        }
    }

    func decline(_ id: String) {
        guard let card = cards.first(where: { $0.id == id }), case .action(var actionCard) = card.kind, actionCard.decline() else { return }
        try? appState.actionLog.record(event: "declined", card: actionCard, detail: "morning card")
        update(id) {
            $0.kind = .action(actionCard)
            $0.dismiss()
        }
    }

    #if DEBUG
    func setCardsForTesting(_ cards: [KaiMorningCard]) {
        self.cards = cards
        lastRunDay = KaiBriefingSchedule.dayKey(for: Date())
        persist()
    }
    #endif

    private func requestCards(input: KaiBriefingInput, now: Date) async throws -> [KaiMorningCard] {
        if !appState.chatModels.contains(appState.selectedModel) { try await appState.refreshChatModels() }
        guard !appState.selectedModel.isEmpty else { throw KaiOllamaError.noChatModel }
        var text = ""
        // No tools: morning cards come from untrusted subjects, so only parsed JSON comes back.
        let stream = ollama.stream(
            model: KaiModelTag.name(from: appState.selectedModel),
            messages: KaiBriefingPrompt.messages(input: input, now: now),
            tools: [],
            temperature: 0.2
        )
        for try await event in stream {
            if case .text(let delta) = event { text += delta }
        }
        return KaiBriefingParser.cards(from: text, input: input, now: now)
    }

    private func update(_ id: String, _ change: (inout KaiMorningCard) -> Void) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        change(&cards[index])
        persist()
    }

    private func persist() {
        guard let lastRunDay else { return }
        try? store.save(KaiBriefingDay(day: lastRunDay, cards: cards))
    }

    /// An action can't still be running after a restart, and it must not run a second time.
    private static func recoveringInterruptedAction(_ card: KaiMorningCard) -> KaiMorningCard {
        guard case .action(var actionCard) = card.kind, actionCard.state == .running else { return card }
        actionCard.finish(.failed("Kai OS closed before this finished, so check whether it happened."))
        var recovered = card
        recovered.kind = .action(actionCard)
        return recovered
    }
}
