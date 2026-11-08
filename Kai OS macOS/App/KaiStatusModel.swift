//
//  KaiStatusModel.swift
//  Kai OS macOS
//
//  Gathers what the menu bar item and the notch strips show. When the local model is the one in
//  use, it checks every 30 seconds whether Ollama answers.
//

import Foundation
import KaiLocalAI
import KaiShared

@MainActor
final class KaiStatusModel: ObservableObject {
    static let shared = KaiStatusModel()

    @Published private(set) var ollamaReachable: Bool?
    private var timer: Timer?
    private var started = false

    func start(appState: AppState) {
        guard !started else { return }
        started = true
        Task { await check(appState: appState) }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self, weak appState] _ in
            guard let appState else { return }
            Task { @MainActor in await self?.check(appState: appState) }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check(appState: AppState) async {
        guard !appState.useCloud else { ollamaReachable = nil; return }
        ollamaReachable = (try? await KaiOllamaClient().listModels()) != nil
    }

    func summary(appState: AppState, desk: KaiDeskController, updates: KaiUpdateController) -> KaiMenuStatus {
        let model = KaiModelTag.name(from: appState.selectedModel)
        return KaiMenuStatus.summarize(KaiMenuStatusInputs(
            ai: appState.useCloud ? .cloud(model: model) : .local(model: model, reachable: ollamaReachable),
            isWorking: appState.isProcessing,
            approvalsWaiting: desk.approvals.count,
            helperAgents: desk.clones.count,
            newCards: appState.morningCards.activeCards.count,
            updateVersion: updates.available?.version.description
        ))
    }
}
