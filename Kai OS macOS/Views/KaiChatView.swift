//
//  KaiChatView.swift
//  Kai OS macOS
//
//  Modern chat interface — bubble messages, glass input, action cards
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiChatView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var inputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            chatHeader
            
            Divider().kaiDivider()
            
            // ── Messages ──
            messagesContent
            
            Divider().kaiDivider()
            
            // ── Screenshot Chip ──
            KaiPendingScreenshotChip().padding(.horizontal, KaiSpacing.regular)
                .padding(.top, KaiSpacing.small)
            
            // ── Input ──
            chatInput
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            inputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            if !($0.object is NSPanel) { inputFocused = true }
        }
    }
    
    // ── Header ──
    private var chatHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(KaiFont.caption2Strong)
                .foregroundStyle(KaiColor.primary)
                .padding(.leading, KaiSpacing.regular)
            
            if appState.chatModels.isEmpty {
                Text("Connect Ollama or add an API key in Settings").font(KaiFont.captionStrong)
                    .foregroundStyle(KaiColor.textTertiary)
            } else {
                Picker("Model", selection: $appState.selectedModel) {
                    ForEach(appState.chatModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            
            Spacer()
            
            Button {
                appState.startNewChat()
            } label: {
                Image(systemName: "plus.bubble")
                    .foregroundStyle(KaiColor.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, KaiSpacing.regular)
        }
        .frame(height: 36)
    }
    
    // ── Messages Area ──
    private var messagesContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: KaiSpacing.medium) {
                    ForEach(appState.messages) { message in
                        MessageBubbleView(message: message, isStreaming: appState.isProcessing && !message.isUser && message.id == appState.messages.last?.id)
                            .transition(.opacity)
                    }
                    
                    Color.clear
                        .frame(height: 1)
                        .id("scroll-bottom")
                }
                .padding(KaiSpacing.regular)
            }
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.bottom)
            .onChange(of: appState.messages) { _, _ in
                withAnimation(.spring(response: 0.3)) {
                    proxy.scrollTo("scroll-bottom", anchor: .bottom)
                }
            }
        }
    }
    
    // ── Input ──
    private var chatInput: some View {
        let canSend = !appState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        return HStack(spacing: KaiSpacing.medium) {
            // ── Text Field ──
            TextField("Ask Kai...", text: $appState.chatDraft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit { send() }
                .kaiInput()
                .frame(maxHeight: 140)
            
            // ── Actions ──
            HStack(spacing: 8) {
                KaiAttachScreenButton()
                
                if appState.isProcessing {
                    Button {
                        appState.cancelReply()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(KaiFont.labelStrong)
                            .foregroundStyle(KaiColor.error)
                    }
                    .buttonStyle(.plain)
                    .help("Stop the reply")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: canSend ? "arrow.up.circle.fill" : "arrow.up.circle")
                            .font(KaiFont.labelStrong)
                            .foregroundStyle(canSend ? KaiColor.primary : KaiColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send")
                }
            }
        }
        .padding(KaiSpacing.regular)
    }
    
    private func send() {
        let canSend = !appState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard canSend, !appState.isProcessing else { return }
        appState.sendMessage(text: appState.chatDraft)
        appState.chatDraft = ""
        inputFocused = true
    }
}
