//
//  KaiActionHistoryView.swift
//  Kai OS macOS
//
//  What Kai has done on this Mac, in plain words: every action that was approved, and how it ended. Where a change
//  can be reversed (marking mail read, a mail rule), there is an Undo. It reads the same action log that is written
//  for every approval, so nothing is shown that was not logged.
//

import KaiActions
import KaiLocalData
import SwiftUI

struct KaiActionHistoryView: View {
    @EnvironmentObject var appState: AppState

    private enum Filter: String, CaseIterable { case all = "All", failed = "Problems", mail = "Mail", writing = "Writing", calendar = "Calendar" }

    @State private var items: [KaiActionHistoryItem] = []
    @State private var filter = Filter.all
    @State private var note: String?
    @State private var busy = false

    private var shown: [KaiActionHistoryItem] {
        items.filter { item in
            switch filter {
            case .all: return true
            case .failed: return item.outcome == .failed
            case .mail: return item.kind.hasPrefix("mail")
            case .writing: return item.kind == "insert_text"
            case .calendar: return item.kind == "calendar_event" || item.kind == "notification"
            }
        }
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: 780)
                .padding(.horizontal, 40).padding(.vertical, 36)
                .frame(maxWidth: .infinity)
        }
        .onAppear { reload() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Activity").font(.system(size: 30, weight: .semibold))
                Text("What Kai did on this Mac after you approved it.").font(.callout).foregroundStyle(.secondary)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 400)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Read the log again")
            }
            Text("Everything Kai changed or wrote after you approved it. Kai never sends mail or deletes anything for good. The log stays on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if let note { Text(note).font(.callout).foregroundStyle(KaiColor.cyan) }
            if shown.isEmpty {
                Text(items.isEmpty ? "Nothing yet. Actions you approve show up here." : "Nothing in this view.").foregroundStyle(.secondary).padding(.top, 20)
            }
            ForEach(shown) { item in row(item) }
        }
    }

    private func reload() { items = appState.actionLog.history(limit: 200) }

    private func row(_ item: KaiActionHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon).foregroundStyle(color(item)).frame(width: 28, height: 28)
                .background(Circle().fill(color(item).opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.heading).fontWeight(.semibold)
                    Text(label(item)).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(color(item).opacity(0.2))).foregroundStyle(color(item))
                    Spacer()
                    Text(item.time.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                if !item.summary.isEmpty { Text(item.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                if let detail = item.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                if let undo = item.undo {
                    Button("Undo: \(undo.change)") { run(undo) }.controlSize(.small).disabled(busy)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kaiLiquidGlass(color(item), radius: 14, glow: 0.05)
    }

    private func label(_ item: KaiActionHistoryItem) -> String {
        switch item.outcome {
        case .succeeded: return "Done"
        case .failed: return "Problem"
        case .declined: return "Declined"
        case .approved: return "Approved"
        case .proposed: return "Proposed"
        }
    }

    private func color(_ item: KaiActionHistoryItem) -> Color {
        switch item.outcome {
        case .succeeded: return KaiColor.cyan
        case .failed: return KaiColor.warning
        default: return .secondary
        }
    }

    /// Pressing Undo is the approval. It is logged like any other action.
    private func run(_ plan: KaiMailCleanupPlan) {
        var card = KaiActionCard(action: .mailCleanup(plan))
        guard card.approve() else { return }
        guard (try? appState.actionLog.record(event: "approved", card: card, detail: "activity page, undo")) != nil else {
            note = "The action log couldn't be written, so nothing was undone."
            return
        }
        busy = true
        let executor = appState.actionExecutor
        Task {
            defer { busy = false }
            do {
                let detail = try await executor.perform(card.action)
                card.finish(.succeeded(detail))
                try? appState.actionLog.record(event: "succeeded", card: card, detail: detail)
                note = detail
                if case .markUnread = plan.operation { appState.applyMailUnread(ids: Set(plan.items.map(\.id))) }
            } catch {
                card.finish(.failed(error.localizedDescription))
                try? appState.actionLog.record(event: "failed", card: card, detail: error.localizedDescription)
                note = error.localizedDescription
            }
            reload()
        }
    }
}
