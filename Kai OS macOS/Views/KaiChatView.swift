//
//  KaiChatView.swift
//  Kai OS macOS
//
//  Modern chat interface — bubble messages, glass input, action cards
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import KaiShared
import SwiftUI

struct KaiChatView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var inputFocused: Bool

    private var hasConversation: Bool { appState.messages.contains { $0.kind != .notice } }

    var body: some View {
        VStack(spacing: 0) {
            if hasConversation {
                chatHeader
                messagesContent
            } else {
                hero
            }
            KaiPendingScreenshotChip().padding(.horizontal, KaiSpacing.regular).padding(.top, KaiSpacing.small)
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

    // ── The home screen, before there is a conversation ──
    private var hero: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(KaiGreeting.text(fullName: NSFullUserName())).font(.system(size: 32, weight: .semibold))
                Text("A little help, whenever you need it.").font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 56).padding(.top, 20)

            Spacer()
            VStack(spacing: 16) {
                KaiLogoMark(size: 88)
                    .padding(.bottom, 6)
                Text("What can I do for you?").font(.system(size: 28, weight: .semibold))
                Text("Your Mac's context is already here. Ask from anywhere.").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    suggestion("calendar", "My day", "What is on my calendar today?")
                    suggestion("envelope", "Unread mail", "Summarize my unread mail from today.")
                    suggestion("number", "Slack", "What happened in Slack since yesterday?")
                    suggestion("globe", "Look something up", "Search the web for ")
                }
                .padding(.top, 8)
            }
            Spacer()
            Spacer()
        }
    }

    private func suggestion(_ symbol: String, _ title: String, _ prompt: String) -> some View {
        Button {
            if prompt.hasSuffix(" ") { appState.chatDraft = prompt; inputFocused = true } else { appState.sendMessage(text: prompt) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .foregroundStyle(.white.opacity(0.88))
        }
        .buttonStyle(.plain)
    }

    // ── Header (once there is a conversation) ──
    private var chatHeader: some View {
        HStack(spacing: 12) {
            if appState.chatModels.isEmpty {
                Text("Connect Ollama or add an API key in Preferences").font(KaiFont.captionStrong)
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
            Button { appState.startNewChat() } label: {
                Label("New chat", systemImage: "plus.bubble").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KaiColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(height: 34)
    }

    // ── Messages Area ──
    private var messagesContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: KaiSpacing.medium) {
                    ForEach(appState.messages.filter { $0.kind != .notice }) { message in
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

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("Ask Kai…", text: $appState.chatDraft, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($inputFocused)
                    .onSubmit { send() }
                KaiAttachScreenButton()
                if appState.isProcessing {
                    Button { appState.cancelReply() } label: {
                        Image(systemName: "stop.circle.fill").font(.system(size: 22)).foregroundStyle(KaiColor.error)
                    }
                    .buttonStyle(.plain)
                    .help("Stop the reply")
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.4))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(canSend ? Color.white : Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send")
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .frame(maxWidth: 820)

            Text("Private by default. Local first.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 28).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    private func send() {
        let canSend = !appState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard canSend, !appState.isProcessing else { return }
        appState.sendMessage(text: appState.chatDraft)
        appState.chatDraft = ""
        inputFocused = true
    }
}
