//
//  KaiSettingsView.swift
//  Kai OS macOS
//
//  Modern settings — card-based layout, grouped sections
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI

struct KaiSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("kai.notch.enabled") private var notchEnabled = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // ── Header ──
                VStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(KaiFont.title3)
                        .foregroundStyle(KaiColor.primary)
                        .kaiGlow()
                    
                    Text("Settings").font(KaiFont.title2)
                    Text("Configure Kai OS for your workflow").font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textTertiary)
                }
                .padding(.top, 8)
                
                Divider().kaiDivider()
                
                // ── Appearance ──
                settingsCard {
                    SectionHeader(title: "Appearance")
                    
                    Picker("Theme", selection: $appState.themeMode) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    
                    // ── AI ──
                    SectionHeader(title: "AI Model")
                    
                    Picker("Model", selection: $appState.selectedModel) {
                        ForEach(appState.chatModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    
                    Button("Refresh Models") {
                        Task { try? await appState.refreshChatModels() }
                    }
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
                }
                
                // ── Cloud ──
                settingsCard {
                    SectionHeader(title: "Cloud AI")
                    
                    Toggle("Use Cloud AI", isOn: $appState.useCloud)
                    
                    if appState.useCloud {
                        Picker("Provider", selection: $appState.selectedCloudProvider) {
                            Text("OpenAI").tag("openai")
                            Text("Anthropic").tag("anthropic")
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 8)
                        
                        Divider().kaiDivider()
                        
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("OpenAI API Key").font(KaiFont.captionStrong)
                                    .foregroundStyle(KaiColor.textTertiary)
                                SecureField("", text: $appState.openAIApiKey)
                                    .kaiInput()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anthropic API Key").font(KaiFont.captionStrong)
                                    .foregroundStyle(KaiColor.textTertiary)
                                SecureField("", text: $appState.anthropicApiKey)
                                    .kaiInput()
                            }
                        }
                        .padding(.top, 12)
                    }
                    
                    Text("Cloud AI uses OpenAI Chat Completions API or Anthropic Messages API. API keys are stored in your keychain.")
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
                }
                
                // ── Notch ──
                settingsCard {
                    SectionHeader(title: "Notch")
                    
                    Toggle("Show at notch", isOn: $notchEnabled)
                        .onChange(of: notchEnabled) {
                            _, _ in KaiNotchWindowController.shared.applyEnabledPreference()
                        }
                    
                    Divider().kaiDivider()
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Toggle chat").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Double ⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Draft email reply").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Hold ⌃⌥ Space").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            Text("Talk / Voice input").font(KaiFont.caption)
                                .foregroundStyle(KaiColor.textSecondary)
                        }
                        
                        HStack {
                            Text("Tap right ⌘").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            Spacer()
                            if KaiSidekickHotkeyMonitor.shared.isRightCommandAvailable {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(KaiColor.success)
                                    .font(KaiFont.captionStrong)
                            } else {
                                Button("Open Permissions") {
                                    appState.activeSidebar = "Permissions"
                                }
                                .font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.warning)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                
                // ── Connections ──
                settingsCard {
                    SectionHeader(title: "Connections")
                    
                    connectionRow(
                        title: "Calendar",
                        connected: appState.calendarConnected,
                        action: appState.connectCalendar
                    )
                    
                    connectionRow(
                        title: "Outlook Calendar",
                        connected: appState.outlookConnected,
                        action: appState.outlookConnected ? appState.disconnectOutlook : appState.connectOutlook
                    )

                    if !appState.outlookConnected {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Microsoft application (client) ID").font(KaiFont.captionStrong)
                                .foregroundStyle(KaiColor.textTertiary)
                            TextField("", text: $appState.outlookClientID)
                                .kaiInput()
                            Text("Register a desktop app in Microsoft Entra with redirect URI kai-os://auth/microsoft and the Calendars.Read permission. Kai only reads your calendar.")
                                .font(KaiFont.caption2Strong)
                                .foregroundStyle(KaiColor.textTertiary)
                        }
                    }

                    if case .failed(let message) = appState.outlookState {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    connectionRow(
                        title: "Mail",
                        connected: appState.mailConnected,
                        action: appState.disconnectMail
                    )
                    
                    connectionRow(
                        title: "Notes",
                        connected: appState.notesConnected,
                        action: appState.disconnectNotes
                    )
                }

                
                // ── About ──
                settingsCard {
                    VStack(spacing: 12) {
                        Image(systemName: "cpu.chip")
                            .font(KaiFont.title2)
                            .foregroundStyle(KaiColor.primary)
                            .kaiGlow()
                        
                        Text("Kai OS").font(KaiFont.title2)
                            .fontWeight(.bold)
                        Text("1.0.0").font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textTertiary)
                        
                        Divider().kaiDivider()
                        
                        Text("Personal AI for macOS").font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textSecondary)
                        
                        Text("© 2026 Kai OS Labs").font(KaiFont.caption2Strong)
                            .foregroundStyle(KaiColor.textTertiary)
                    }
                }
                
                // ── Privacy ──
                settingsCard {
                    VStack(spacing: 8) {
                        Text("Privacy").font(KaiFont.bodyStrong)
                            .foregroundStyle(KaiColor.textPrimary)
                        
                        Text("Chat stays on this Mac when using a local Ollama model. Cloud AI (OpenAI/Anthropic) sends data to their services — configure API keys above. Approved actions are logged in ~/Library/Application Support/Kai OS/action-log.jsonl.")
                            .font(KaiFont.caption)
                            .foregroundStyle(KaiColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 20)
            }
            .padding(KaiSpacing.regular)
        }
        .navigationTitle("Settings")
    }
    
    // ── Card Wrapper ──
    private func settingsCard<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(KaiSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                .fill(KaiColor.surfaceBg)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: KaiSpacing.cornerRadiusLarge)
                        .stroke(KaiColor.border.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
    
    // ── Connection Row ──
    private func connectionRow(
        title: String,
        connected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: connected ? "checkmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(connected ? KaiColor.success : KaiColor.textTertiary)
                .font(KaiFont.captionStrong)
            
            Text(title).font(KaiFont.bodyStrong)
            
            Spacer()
            
            if connected {
                Button("Disconnect") { action() }
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
            } else {
                Button("Connect") { action() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
    }
}

// ── Section Header ──
private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title).font(KaiFont.captionStrong)
            .foregroundStyle(KaiColor.textTertiary)
            .textCase(.uppercase)
            .padding(.bottom, 4)
    }
}
