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
                
                // ── Knowledge base ──
                settingsCard {
                    SectionHeader(title: "Knowledge base")

                    Text(appState.knowledgeDocumentCount == 0
                         ? "Nothing indexed yet. Kai searches the Markdown and text files in your knowledge folder, plus Notes, Calendar and Mail subjects for the sources you've connected. It all stays on this Mac."
                         : appState.knowledgeCounts.sorted { $0.key < $1.key }
                            .map { "\(AppState.knowledgeSourceNames[$0.key] ?? $0.key): \($0.value)" }
                            .joined(separator: " · "))
                        .font(KaiFont.caption)
                        .foregroundStyle(KaiColor.textSecondary)

                    HStack {
                        Button(appState.isIndexingKnowledge ? "Indexing…" : "Index now") { appState.indexKnowledge() }
                            .buttonStyle(.borderedProminent)
                            .disabled(appState.isIndexingKnowledge)
                        Button("Open folder") { appState.openKnowledgeFolder() }
                    }
                    .controlSize(.small)

                    Text(appState.knowledgeFolder.path)
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)

                    if case .failed(let message) = appState.knowledgeState {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }
                }
                .onAppear { appState.refreshKnowledgeCounts() }

                // ── Night Shift ──
                settingsCard {
                    SectionHeader(title: "Night Shift")

                    Toggle("Prepare things overnight", isOn: Binding(
                        get: { appState.nightShift.enabled },
                        set: { var next = appState.nightShift; next.enabled = $0; appState.updateNightShift(next) }
                    ))

                    if appState.nightShift.enabled {
                        DatePicker("Time", selection: Binding(
                            get: { Calendar.current.date(from: DateComponents(hour: appState.nightShift.hour, minute: appState.nightShift.minute)) ?? Date() },
                            set: {
                                var next = appState.nightShift
                                next.hour = Calendar.current.component(.hour, from: $0)
                                next.minute = Calendar.current.component(.minute, from: $0)
                                appState.updateNightShift(next)
                            }
                        ), displayedComponents: .hourAndMinute)
                        if let next = appState.nightShift.nextRun(after: Date()) {
                            Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
                                .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                        }
                    }

                    if let record = appState.nightShiftRecord {
                        Text("Last run \(record.ranAt.formatted(date: .abbreviated, time: .shortened)). \(record.summary)")
                            .font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    if let message = appState.nightShiftMessage {
                        Text(message).font(KaiFont.caption).foregroundStyle(KaiColor.textSecondary)
                    }

                    Button(appState.isRunningNightShift ? "Running…" : "Run now") { appState.runNightShiftNow() }
                        .controlSize(.small)
                        .disabled(appState.isRunningNightShift)

                    Text("At the set time, Kai OS starts in the background, updates the knowledge base and prepares your morning cards, then quits. It only prepares cards: nothing is sent or changed without your approval. It skips the run in Low Power Mode, when the Mac is hot, or on a low battery. A sleeping Mac is not woken; if the Mac is asleep at that time, the job runs when it wakes. This adds a launch agent at ~/Library/LaunchAgents/ai.kai.nightshift.plist, and turning it off removes it.")
                        .font(KaiFont.caption2Strong)
                        .foregroundStyle(KaiColor.textTertiary)
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
