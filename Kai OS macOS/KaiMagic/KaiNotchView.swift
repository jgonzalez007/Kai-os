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
                KaiNotchPanelContent(model: model, appState: appState, controller: controller, topInset: notchHeight)
                    .transition(.opacity)
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

    private var input: some View {
        HStack(spacing: 8) {
            TextField("Ask Kai...", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit(send)
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
        guard canSend, !appState.isProcessing else { return }
        appState.sendMessage(text: model.draft)
        model.draft = ""
        inputFocused = true
    }
}
