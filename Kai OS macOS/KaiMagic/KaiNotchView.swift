//
//  KaiNotchView.swift
//  Kai OS macOS
//
//  The notch's contents: wings with activity, and a full chat panel that shares the
//  conversation with the main window.
//

import KaiNotchCore
import SwiftUI
import KaiShared

struct KaiNotchView: View {
    @ObservedObject var model: KaiNotchModel
    @ObservedObject var appState: AppState
    let controller: KaiNotchWindowController
    @ObservedObject private var desk = KaiDeskController.shared
    @ObservedObject private var statusModel = KaiStatusModel.shared
    @ObservedObject private var updates = KaiUpdateController.shared
    @State private var dropTargeted = false
    @AppStorage(KaiMotion.key) private var motion = true

    private var size: CGSize {
        model.layout?.frame(for: model.surface).size ?? .zero
    }

    private var notchHeight: CGFloat {
        model.layout?.notch.height ?? 0
    }

    private var isExpanded: Bool {
        model.surface == .expanded
    }

    var body: some View {
        ZStack(alignment: .top) {
            KaiNotchShape(topRadius: isExpanded ? 14 : 8, bottomRadius: isExpanded ? 22 : 10)
                .fill(isExpanded ? AnyShapeStyle(KaiNotchStyle.panelFill) : AnyShapeStyle(Color.black))
            if isExpanded {
                // A soft colored edge, like a light behind the panel. Black at the top so it
                // still merges with the hardware notch.
                KaiNotchShape(topRadius: 14, bottomRadius: 22)
                    .stroke(KaiNotchStyle.glow, lineWidth: 5)
                    .blur(radius: 4)
                    .opacity(desk.approvals.isEmpty ? 0.55 : 0.95)
                    .allowsHitTesting(false)
                KaiNotchShape(topRadius: 14, bottomRadius: 22)
                    .stroke(KaiNotchStyle.glow, lineWidth: 1)
                    .opacity(0.8)
                    .allowsHitTesting(false)
            }
            if isExpanded {
                if model.panelMode == .reply, let doubleTap = controller.doubleTap {
                    KaiNotchReplyContent(model: model, doubleTap: doubleTap, controller: controller, topInset: notchHeight)
                        .transition(.opacity)
                } else {
                    KaiNotchPanelContent(model: model, appState: appState, controller: controller, topInset: notchHeight)
                        .transition(.opacity)
                }
            } else if model.surface == .peek {
                wings.transition(.opacity)
            } else if model.surface == .status {
                statusStrips.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { controller.expand() } }
        // Dropping files, links or text on the notch puts them on the Shelf.
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $dropTargeted) { providers in
            desk.acceptDrop(providers)
        }
        .onChange(of: dropTargeted) { _, targeted in
            if targeted {
                desk.tab = .shelf
                controller.expand()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.surface)
    }

    /// Slim strips beside the notch: the Kai mark on the left, a colored dot on the right.
    private var statusStrips: some View {
        let summary = statusModel.summary(appState: appState, desk: desk, updates: updates)
        let color: Color = {
            switch summary.level {
            case .idle: return .green
            case .working: return .blue
            case .needsYou: return .orange
            case .attention: return .red
            }
        }()
        return HStack(spacing: 0) {
            Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: KaiNotchLayout.statusWingWidth)
            Spacer(minLength: 0)
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: summary.level == .idle ? 0 : 3)
                .frame(width: KaiNotchLayout.statusWingWidth)
        }
        .frame(height: notchHeight)
        .help("Kai OS: \(summary.title)")
    }

    private var wings: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: KaiNotchLayout.wingWidth)
            Spacer(minLength: 0)
            rightWing.frame(width: KaiNotchLayout.wingWidth)
                .animation(motion ? .spring(response: 0.35, dampingFraction: 0.7) : nil, value: model.activity)
        }
        .frame(height: notchHeight)
    }

    @ViewBuilder
    private var leftWing: some View {
        ZStack {
            switch model.activity {
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(motion ? .scale(scale: 0.2).combined(with: .opacity) : .identity)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    .transition(motion ? .scale(scale: 0.2).combined(with: .opacity) : .identity)
            case .idle, .running:
                KaiSpinningLogo(spinning: model.activity == .running)
                    .transition(motion ? .scale(scale: 0.2).combined(with: .opacity) : .identity)
            }
        }
        .animation(motion ? .spring(response: 0.35, dampingFraction: 0.55) : nil, value: model.activity)
    }

    @ViewBuilder
    private var rightWing: some View {
        if motion && model.activity == .running && model.peekText == nil {
            KaiWorkingPill().transition(.opacity)
        } else {
            Text(wingText).font(.caption).foregroundStyle(.white.opacity(0.8))
                .transition(motion ? .opacity.combined(with: .scale(scale: 0.8)) : .identity)
        }
    }

    private var wingText: String {
        if let note = model.peekText { return note }
        if model.activity == .idle, !desk.clones.isEmpty { return "Claude ·\(desk.clones.count)" }
        switch model.activity {
        case .idle: return "Ask"
        case .running: return "Working"
        case .done: return "Done"
        case .failed: return "Failed"
        }
    }
}

private struct KaiNotchReplyContent: View {
    @ObservedObject var model: KaiNotchModel
    @ObservedObject var doubleTap: KaiDoubleTapController
    let controller: KaiNotchWindowController
    let topInset: CGFloat

    @FocusState private var instructionFocused: Bool

    private var title: String {
        guard case .mail(_, let source) = doubleTap.context else { return "Reply to the email on screen" }
        let name = source.sender.split(separator: "<").first.map { $0.trimmingCharacters(in: .whitespaces) }
        return "Reply to \(name.flatMap { $0.isEmpty ? nil : $0 } ?? source.sender)"
    }

    private var subject: String? {
        guard case .mail(_, let source) = doubleTap.context else { return nil }
        return source.subject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.semibold).lineLimit(1)
                    if let subject { Text(subject).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                statusLabel
                Button(action: controller.collapse) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Close and discard this draft")
            }
            content
            if let warning = doubleTap.factWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if doubleTap.context != nil { instructionRow }
            actionRow
        }
        .padding(.top, topInset + 8)
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            instructionFocused = true
        }
        .onExitCommand { controller.collapse() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch doubleTap.phase {
        case .reading: Text("Reading…").font(.caption).foregroundStyle(.secondary)
        case .drafting: Text("Drafting…").font(.caption).foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .failed(let message) = doubleTap.phase {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $doubleTap.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .disabled(doubleTap.phase != .ready)
                    .padding(6)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                if doubleTap.draft.isEmpty && doubleTap.phase != .ready {
                    ProgressView().controlSize(.small).padding(14)
                }
            }
        }
    }

    private var instructionRow: some View {
        HStack(spacing: 8) {
            TextField(model.voicePhase == .listening ? "Listening…" : "Tell Kai what to say, then press Return", text: $doubleTap.instruction)
                .textFieldStyle(.plain)
                .focused($instructionFocused)
                .padding(10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { doubleTap.regenerate() }
            Button(action: controller.toggleVoice) {
                Image(systemName: model.voicePhase == .listening ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(model.voicePhase == .listening ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.voicePhase == .transcribing)
            .help("Say what the reply should say")
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Redraft") { doubleTap.regenerate() }
                .disabled(doubleTap.context == nil || doubleTap.phase == .drafting || doubleTap.phase == .reading)
            Button("Copy") { doubleTap.copyDraft() }
                .disabled(!doubleTap.canCopy)
            Spacer()
            outcome
            if doubleTap.destination == .awaitingCursor && doubleTap.phase == .ready && doubleTap.openState == nil {
                Text("Click in your reply box, then:").font(.caption).foregroundStyle(.secondary)
            }
            // No keyboard shortcut: pressing Return in the instruction field must only redraft.
            Button(doubleTap.writeButtonTitle) { doubleTap.writeDraft() }
                .buttonStyle(.borderedProminent)
                .disabled(!doubleTap.canWrite)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch doubleTap.openState {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded(let detail):
            Label(detail, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green).lineLimit(2)
        case .failed(let detail):
            Label(detail, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(3)
        default:
            EmptyView()
        }
    }
}

private struct KaiNotchPanelContent: View {
    @ObservedObject var model: KaiNotchModel
    @ObservedObject var appState: AppState
    let controller: KaiNotchWindowController
    let topInset: CGFloat
    @ObservedObject private var desk = KaiDeskController.shared

    @FocusState private var inputFocused: Bool

    private var transcript: [Message] {
        appState.messages.filter { $0.kind != .notice }
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let approval = desk.approvals.first {
                KaiApprovalCard(desk: desk, approval: approval)
            } else {
                switch desk.tab {
                case .chat: chatBody
                case .shelf: KaiShelfPanel(desk: desk)
                case .clipboard: KaiClipboardPanel(desk: desk)
                case .claude: KaiClaudePanel(desk: desk)
                }
            }
        }
        .padding(.top, topInset + 8)
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .onAppear { if desk.tab == .chat { inputFocused = true } }
        .onChange(of: desk.tab) { _, tab in if tab == .chat { inputFocused = true } }
        .onExitCommand { controller.collapse() }
    }

    @ViewBuilder
    private var chatBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if transcript.isEmpty {
                    Text("Ask anything. Replies come from your local model, and this chat also appears in the main window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        KaiNotchChip(symbol: "calendar", title: "My day") { send("What is on my calendar today?") }
                        KaiNotchChip(symbol: "envelope", title: "Unread mail") { send("Summarize my unread mail from today.") }
                        KaiNotchChip(symbol: "number", title: "Slack") { send("What happened in Slack since yesterday?") }
                    }
                    .padding(.top, 4)
                }
                ForEach(transcript) { MessageBubbleView(message: $0, isStreaming: appState.isProcessing && $0.id == transcript.last?.id && !$0.isUser) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        KaiPendingScreenshotChip().environmentObject(appState)
        input
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    KaiSpinningLogo(spinning: appState.isProcessing)
                    Text("Kai").fontWeight(.semibold)
                    Text(KaiModelTag.name(from: appState.selectedModel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(width: 150, alignment: .leading)
                Spacer(minLength: 0)
                KaiDeskTabBar(desk: desk)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Button(action: appState.startNewChat) { Image(systemName: "plus.bubble") }
                        .buttonStyle(.plain)
                        .help("New Chat")
                    Button(action: controller.openMainWindow) { Image(systemName: "macwindow") }
                        .buttonStyle(.plain)
                        .help("Open Kai OS")
                }
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 150, alignment: .trailing)
            }
            // On its own line, so it can never sit on top of the model name.
            if let hint = appState.suggestions.first {
                adaptiveHint(hint)
            }
        }
    }

    private func adaptiveHint(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.purple)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: String {
        switch model.voicePhase {
        case .idle: return "Ask Kai..."
        case .listening: return "Listening…"
        case .transcribing: return "Finishing…"
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit(send)
            KaiAttachScreenButton().environmentObject(appState)
            Button(action: controller.toggleVoice) {
                Image(systemName: model.voicePhase == .listening ? "mic.fill" : "mic")
                    .font(.title3)
                    .foregroundStyle(model.voicePhase == .listening ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(model.voicePhase == .transcribing)
            .help(model.voicePhase == .listening ? "Stop and send" : "Talk")
            if appState.isProcessing {
                Button(action: appState.cancelReply) {
                    Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop the reply")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(canSend ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
        }
    }

    private func send(_ text: String) {
        guard !appState.isProcessing else { return }
        appState.sendMessage(text: text)
    }

    private func send() {
        guard canSend, !appState.isProcessing, model.voicePhase == .idle else { return }
        appState.sendMessage(text: model.draft)
        model.draft = ""
        inputFocused = true
    }
}


/// Colors shared by the notch panels.
enum KaiNotchStyle {
    /// Black at the top (so the panel melts into the hardware notch), then a deep navy.
    static let panelFill = LinearGradient(
        stops: [
            .init(color: Color(red: 0.02, green: 0.03, blue: 0.05), location: 0),
            .init(color: Color(red: 0.06, green: 0.09, blue: 0.15), location: 0.25),
            .init(color: Color(red: 0.08, green: 0.12, blue: 0.20), location: 1)
        ],
        startPoint: .top, endPoint: .bottom
    )

    static let glow = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.45, blue: 0.62), Color(red: 0.70, green: 0.45, blue: 1.0),
            Color(red: 0.35, green: 0.62, blue: 1.0), Color(red: 0.35, green: 0.85, blue: 0.62),
            Color(red: 1.0, green: 0.70, blue: 0.35)
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

/// A dark capsule button, used for quick actions.
struct KaiNotchChip: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
    }
}
