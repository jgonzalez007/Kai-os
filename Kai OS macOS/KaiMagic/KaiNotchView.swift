//
//  KaiNotchView.swift
//  Kai OS macOS
//
//  The notch's contents: wings with activity, and a full chat panel that shares the
//  conversation with the main window.
//

import KaiNotchCore
import SwiftUI

struct KaiNotchView: View {
    @ObservedObject var model: KaiNotchModel
    @ObservedObject var appState: AppState
    let controller: KaiNotchWindowController

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
                .fill(.black)
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
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { controller.expand() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.surface)
    }

    private var wings: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: KaiNotchLayout.wingWidth)
            Spacer(minLength: 0)
            rightWing.frame(width: KaiNotchLayout.wingWidth)
        }
        .frame(height: notchHeight)
    }

    @ViewBuilder
    private var leftWing: some View {
        switch model.activity {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .idle, .running:
            KaiSpinningLogo(spinning: model.activity == .running)
        }
    }

    private var rightWing: some View {
        Text(wingText).font(.caption).foregroundStyle(.white.opacity(0.8))
    }

    private var wingText: String {
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

    private var isMailReply: Bool {
        if case .mail = doubleTap.context { return true }
        return false
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
            if isMailReply {
                // No keyboard shortcut: pressing Return in the instruction field must never open it.
                Button("Open Reply in Mail") { doubleTap.openInMail() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!doubleTap.canOpenInMail)
            } else if doubleTap.phase == .ready {
                Text("Copy this into your email.").font(.caption).foregroundStyle(.secondary)
            }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if transcript.isEmpty {
                        Text("Ask anything. Replies come from your local model, and this chat also appears in the main window.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(transcript) { MessageBubbleView(message: $0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            KaiPendingScreenshotChip().environmentObject(appState)
            input
        }
        .padding(.top, topInset + 8)
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .onAppear { inputFocused = true }
        .onExitCommand { controller.collapse() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            KaiSpinningLogo(spinning: appState.isProcessing)
            Text("Kai").fontWeight(.semibold)
            Text(appState.selectedModel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button(action: appState.startNewChat) { Image(systemName: "plus.bubble") }
                .buttonStyle(.plain)
                .help("New Chat")
            Button(action: controller.openMainWindow) { Image(systemName: "macwindow") }
                .buttonStyle(.plain)
                .help("Open Kai OS")
        }
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

    private func send() {
        guard canSend, !appState.isProcessing, model.voicePhase == .idle else { return }
        appState.sendMessage(text: model.draft)
        model.draft = ""
        inputFocused = true
    }
}
