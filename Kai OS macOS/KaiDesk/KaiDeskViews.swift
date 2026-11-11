//
//  KaiDeskViews.swift
//  Kai OS macOS
//
//  The notch panels for the Desk: tab bar, Shelf, Clipboard, Claude Code, and the approval card.
//  The notch is always dark, so these use plain white-on-black styling.
//

import KaiDesk
import KaiShared
import SwiftUI

struct KaiDeskTabBar: View {
    @ObservedObject var desk: KaiDeskController
    @AppStorage(KaiMotion.key) private var motion = true
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KaiDeskController.Tab.allCases) { tab in
                Button { desk.tab = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13))
                        .frame(width: 34, height: 26)
                        .background {
                            if desk.tab == tab {
                                if motion {
                                    // One highlight that slides from tab to tab.
                                    RoundedRectangle(cornerRadius: 9).fill(Color.blue.opacity(0.28))
                                        .matchedGeometryEffect(id: "tabHighlight", in: highlight)
                                } else {
                                    RoundedRectangle(cornerRadius: 9).fill(Color.blue.opacity(0.28))
                                }
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if tab == .claude && !desk.approvals.isEmpty {
                                Text("\(desk.approvals.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .background(.orange, in: Capsule())
                                    .foregroundStyle(.black)
                                    .offset(x: 4, y: -3)
                            }
                        }
                        .foregroundStyle(desk.tab == tab ? Color.white : Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .animation(motion ? .spring(response: 0.32, dampingFraction: 0.74) : nil, value: desk.tab)
        .padding(3)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Shelf

struct KaiShelfPanel: View {
    @ObservedObject var desk: KaiDeskController

    var body: some View {
        VStack(spacing: 8) {
            if desk.shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                    Text("Drop files, links or text here").font(.callout)
                    Text("Drag them out later. Files stay where they are: the Shelf keeps a reference, not a copy.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(desk.shelf.items) { item in
                            KaiShelfRow(desk: desk, item: item)
                        }
                    }
                }
            }
            if desk.showUndo, let title = desk.undoTitle {
                HStack {
                    Text("Removed “\(title)”").font(.caption).lineLimit(1)
                    Spacer()
                    Button("Undo") { desk.undoDragOut() }.controlSize(.small)
                }
                .padding(8).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("\(desk.shelf.items.count) item\(desk.shelf.items.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { desk.clearShelf() }.controlSize(.small).disabled(desk.shelf.items.isEmpty)
            }
        }
    }
}

private struct KaiShelfRow: View {
    @ObservedObject var desk: KaiDeskController
    let item: KaiShelfItem

    private var symbol: String {
        switch item.kind {
        case .file: return "doc"
        case .link: return "link"
        case .text: return "text.alignleft"
        }
    }

    private var missing: Bool {
        item.kind == .file && !FileManager.default.fileExists(atPath: item.value)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1).strikethrough(missing)
                if let detail = item.detail {
                    Text(missing ? "Moved or deleted" : detail).font(.caption2).foregroundStyle(missing ? Color.orange : Color.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Button { desk.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                .buttonStyle(.plain).foregroundStyle(item.pinned ? Color.yellow : Color.secondary)
                .help(item.pinned ? "Unpin: it leaves the Shelf when dragged out" : "Pin: it stays when dragged out")
            Button { desk.remove(item) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from the Shelf")
        }
        .font(.callout)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { desk.open(item) }
        .onDrag { desk.dragStarted(item) }
    }
}

// MARK: Clipboard

struct KaiClipboardPanel: View {
    @ObservedObject var desk: KaiDeskController
    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            if !desk.clipboardEnabled {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.title2).foregroundStyle(.secondary)
                    Text("Clipboard history is off").font(.callout)
                    Text("When on, Kai OS remembers your last 50 text copies on this Mac. It skips password managers, terminals and dictation, and anything an app marks as secret.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Turn on") { desk.clipboardEnabled = true }.kaiProminent()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Search copies", text: $query)
                    .textFieldStyle(.plain).padding(8)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                let rows = desk.clipboard.matching(query)
                if rows.isEmpty {
                    Text(query.isEmpty ? "Nothing copied yet." : "No matches.").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(rows) { entry in
                                HStack(spacing: 8) {
                                    Text(entry.preview).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(entry.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                                    Button { desk.togglePin(entry) } label: { Image(systemName: entry.pinned ? "pin.fill" : "pin") }
                                        .buttonStyle(.plain).foregroundStyle(entry.pinned ? Color.yellow : Color.secondary)
                                    Button { desk.remove(entry) } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture { desk.copyBack(entry) }
                                .help("Click to copy again")
                            }
                        }
                    }
                }
                HStack {
                    Text("Click an entry to copy it again. Kept on this Mac only.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { desk.clearClipboard() }.controlSize(.small).disabled(desk.clipboard.entries.isEmpty)
                }
            }
        }
    }
}

// MARK: Claude Code

struct KaiClaudePanel: View {
    @ObservedObject var desk: KaiDeskController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !desk.hooksEnabled {
                VStack(spacing: 8) {
                    Image(systemName: "terminal").font(.title2).foregroundStyle(.secondary)
                    Text("Claude Code is not connected").font(.callout)
                    Text("Approve or deny Claude Code's permission requests here, see when a task is done and which helper agents are running. Setup is in Settings → Desk.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Start listening") { desk.hooksEnabled = true }.kaiProminent()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Helper agents").font(.caption).foregroundStyle(.secondary)
                if desk.clones.isEmpty {
                    Text("None running.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(desk.clones) { clone in KaiCloneCard(clone: clone) }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("Recently finished").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                if desk.recentDone.isEmpty {
                    Text("Nothing yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(desk.recentDone.enumerated()), id: \.offset) { _, done in
                        Label(done.text, systemImage: done.failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(done.failed ? Color.red : Color.green)
                    }
                }
                Spacer()
                Text(desk.hooksMessage).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KaiApprovalCard: View {
    @ObservedObject var desk: KaiDeskController
    let approval: KaiDeskController.Approval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text("Claude needs your OK").fontWeight(.semibold)
                Spacer()
                if desk.approvals.count > 1 {
                    Text("1 of \(desk.approvals.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(approval.event.project).font(.caption).bold()
                if let tool = approval.event.toolName { Text("· \(tool)").font(.caption).foregroundStyle(.secondary) }
                if let agent = approval.event.agentType { Text("· from \(KaiHookTracker.label(forAgentType: agent))").font(.caption).foregroundStyle(.secondary) }
            }
            ScrollView {
                Text(approval.event.toolSummary ?? "No details were sent with this request.")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                if desk.keyboardShortcutsWork {
                    Text("⌃⌥Y allow · ⌃⌥N deny").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Nothing runs until you press Allow.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Deny") { desk.decide(approval, .deny) }
                Button("Allow") { desk.decide(approval, .allow) }.kaiProminent()
            }
        }
    }
}

/// One helper agent: a small Kai mark, its name, and a colored status.
private struct KaiCloneCard: View {
    let clone: KaiHookClone

    var body: some View {
        let color: Color = clone.waitingForYou ? .orange : .blue
        VStack(spacing: 5) {
            ZStack {
                if clone.waitingForYou {
                    Circle().fill(Color.orange.opacity(0.28)).blur(radius: 8).frame(width: 52, height: 52)
                }
                KaiLogoMark(size: 30, pulsing: !clone.waitingForYou)
            }
            .frame(width: 52, height: 44)
            Text(clone.label).font(.callout).lineLimit(1).frame(maxWidth: 76)
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(clone.waitingForYou ? "needs you" : "working").font(.caption).foregroundStyle(color)
            }
        }
    }
}

// MARK: Stats

/// Clock, battery, CPU, memory and heat as small glass cards, and quick actions for the notch.
struct KaiStatsPanel: View {
    let controller: KaiNotchWindowController
    @ObservedObject private var sampler = KaiStatsSampler.shared
    @State private var chosen = KaiStatsItem.stored()

    var body: some View {
        VStack(spacing: 12) {
            if chosen.isEmpty {
                Text("No stats are turned on. Choose them in Preferences → Notch & Desk.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if chosen.contains(.clock) {
                    VStack(spacing: 2) {
                        Text(sampler.now, format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(sampler.now, format: .dateTime.weekday(.wide).month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                let gauges = KaiStatsItem.allCases.filter { $0 != .clock && chosen.contains($0) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: min(3, max(1, gauges.count))), spacing: 10) {
                    ForEach(gauges, id: \.self) { item in KaiMetricCard(item: item, snapshot: sampler.snapshot) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button { controller.hideNotch() } label: { Label("Hide notch", systemImage: "eye.slash") }
                Spacer()
                Button { controller.openPreferences() } label: { Label("Stats settings", systemImage: "slider.horizontal.3") }
            }
            .controlSize(.small)
        }
        .onAppear { chosen = KaiStatsItem.stored(); sampler.start() }
        .onDisappear { sampler.stop() }
    }
}

private struct KaiMetricCard: View {
    let item: KaiStatsItem
    let snapshot: KaiStatsSnapshot

    private var tint: Color {
        switch item {
        case .cpu: return KaiColor.cyan
        case .memory: return KaiColor.violet
        case .battery: return KaiColor.magenta
        case .thermal: return KaiColor.liquidBlue
        case .clock: return .white
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(item.title.uppercased()).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.white.opacity(0.5))
            Text(snapshot.value(for: item)).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(tint)
            if let gauge = snapshot.gauge(for: item) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(tint).frame(maxWidth: .infinity).scaleEffect(x: max(0.02, gauge), y: 1, anchor: .leading)
                }
                .frame(height: 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
