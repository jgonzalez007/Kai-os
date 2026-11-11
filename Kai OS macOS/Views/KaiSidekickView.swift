//
//  KaiSidekickView.swift
//  Kai OS macOS
//
//  Give Kai a task and it operates your Mac for you, one approved step at a time.
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import SwiftUI
import KaiAgent

struct KaiSidekickView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var agent: KaiAgentController

    private enum Tab: String, CaseIterable { case task = "Task", settings = "Settings" }
    @State private var tab = Tab.task

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sidekick").font(.system(size: 26, weight: .semibold))
                Spacer()
                KaiThemedSegmented(options: Tab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
                    .frame(width: KaiTheme.isCobalt ? nil : 180)
            }
            .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 10)

            if tab == .settings {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Make everyday help feel like your own.").foregroundStyle(.secondary)
                        KaiSidekickSettingsView()
                    }
                    .frame(maxWidth: 780).padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
            } else {
                taskPage
            }
        }
    }

    /// One box for each {blank} in the task, when a recipe is picked.
    @ViewBuilder private var recipeBlanks: some View {
        if let recipe = agent.pendingRecipe {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Recipe: \(recipe.name)", systemImage: "list.bullet.rectangle").font(KaiFont.captionStrong)
                    Spacer()
                    if agent.task.trimmingCharacters(in: .whitespacesAndNewlines) != recipe.task {
                        Button("Keep this wording") { agent.updatePendingRecipeTask() }.controlSize(.small).disabled(agent.isRunning)
                    }
                    Button("Not this recipe") { agent.clearRecipe() }.controlSize(.small).disabled(agent.isRunning)
                }
                ForEach(KaiAgentRecipes.blanks(in: agent.task), id: \.self) { name in
                    HStack {
                        Text(name).font(KaiFont.caption).frame(width: 110, alignment: .leading)
                        TextField("", text: Binding(get: { agent.blankValues[name] ?? "" }, set: { agent.blankValues[name] = $0 }))
                            .textFieldStyle(.roundedBorder).disabled(agent.isRunning)
                    }
                }
                Text("Put a part that changes in curly brackets, like {person}, and Kai asks for it each time. The steps that worked last time guide the run; each one is still checked on the screen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// After a task that worked: keep it under a name.
    @ViewBuilder private var saveCard: some View {
        if agent.canSaveRecipe, !agent.isRunning {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("That worked. Keep it to run again:").font(KaiFont.caption)
                TextField("Name", text: $agent.recipeName).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                Button("Save recipe") { agent.saveRecipe() }.kaiProminent()
            }
            .padding(10)
            .background(KaiColor.surfaceBg, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var recipesList: some View {
        if !agent.recipes.isEmpty {
            GroupBox("Recipes") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(agent.recipes) { recipe in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(recipe.name).fontWeight(.medium).lineLimit(1)
                                Text("\(recipe.steps.count) steps" + (recipe.runs > 0 ? " · run \(recipe.runs) time\(recipe.runs == 1 ? "" : "s")" : "")
                                     + (KaiAgentRecipes.blanks(in: recipe.task).isEmpty ? "" : " · asks for " + KaiAgentRecipes.blanks(in: recipe.task).joined(separator: ", ")))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Use") { agent.useRecipe(recipe) }.controlSize(.small).disabled(agent.isRunning)
                            Button { agent.deleteRecipe(recipe.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).disabled(agent.isRunning).help("Delete this recipe")
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    private var taskPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sidekick does a task in your other apps. Describe it and Kai will do it in your other apps by looking at the screen and using the mouse and keyboard, with a ring where it clicks. It uses a local model, so what's on your screen never leaves this Mac.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                TextEditor(text: $agent.task)
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 110)
                    .padding(6)
                    .kaiTextBox()
                    .disabled(agent.isRunning)
                    .overlay(alignment: .topLeading) {
                        if agent.task.isEmpty {
                            Text("For example: open Notes and create a note called Shopping with milk and eggs")
                                .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                        }
                    }

                recipeBlanks

                if KaiTheme.isCobalt {
                    HStack(spacing: 12) {
                        Text("Control").font(KaiFont.captionStrong)
                        KaiThemedSegmented(options: [(KaiAgentMode.askEach, "Ask me before every action"), (KaiAgentMode.auto, "Run on its own")], selection: $agent.mode)
                    }
                    .disabled(agent.isRunning)
                } else {
                    Picker("Control", selection: $agent.mode) {
                        Text("Ask me before every action").tag(KaiAgentMode.askEach)
                        Text("Run on its own").tag(KaiAgentMode.auto)
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(agent.isRunning)
                }

                Text(agent.mode == .askEach
                     ? "Every click, keystroke and shortcut waits for your Approve."
                     : "Clicks, typing and scrolling run by themselves. It also makes notes, events and mail drafts on its own. Kai still asks before quitting or closing, before ⌘Return, and before Return or a new line in a chat app such as Slack or Messages, where that sends. Use this only for tasks where a wrong click is harmless.")
                    .font(KaiFont.caption).foregroundStyle(.secondary)

                HStack {
                    if agent.isRunning {
                        Button("Stop") { agent.stop() }.tint(.red)
                    } else {
                        Button("Start") { agent.start(appState: appState) }
                            .kaiProminent()
                            .disabled(agent.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if agent.isRunning { ProgressView().controlSize(.small) }
                }

                if let message = agent.message {
                    Text(message).font(KaiFont.caption).foregroundStyle(.orange)
                }

                saveCard
                recipesList

                GroupBox("Safety") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• Esc, the Stop button, or using your own mouse or keyboard stops it at once.")
                        Text("• It never works in Terminal, System Settings, password managers or Keychain Access, and never while Kai's own window is in front.")
                        Text("• It stops after \(KaiAgentEffort.stored().limits.maxSteps) steps or \(Int(KaiAgentEffort.stored().limits.maxDuration / 60)) minutes. Change this on the Settings tab, under Speed & intelligence.")
                        Text("• It can open an app by name, but never Terminal, System Settings or the other blocked apps. It reads the names and positions of buttons and fields in the front window (never what is typed in them) to click in the right place.")
                        Text("• Where a job has a direct route it skips the screen: it can make a note, add a calendar event, open a mail draft or a link, read your calendar, recent mail, Slack, notes and files, and read what you last copied. Those reads only happen with a local model: with Claude they are refused. In Ask each time, anything that makes something waits for your Approve. It never sends mail.")
                        Text("• When it is stuck on something only you can decide, it asks one question with two answers, up to three times. It never asks for passwords. When it says it is done it has to say what on the screen shows it, and it can say it could not finish.")
                        Text("• Everything it proposes or does is logged in ~/Library/Application Support/Kai OS/agent-log.jsonl. Screenshots are not saved.")
                        Text("• Text on screen is treated as untrusted. Kai won't act on instructions it reads there.")
                    }
                    .font(KaiFont.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                if !agent.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What happened").font(KaiFont.bodyStrong)
                        ForEach(agent.lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: icon(line.kind)).foregroundStyle(color(line.kind)).frame(width: 16)
                                Text(line.text).font(KaiFont.caption)
                                    .foregroundStyle(line.kind == .thought ? .secondary : .primary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func icon(_ kind: KaiAgentController.LineKind) -> String {
        switch kind {
        case .thought: return "bubble.left"
        case .proposed: return "questionmark.circle"
        case .performed: return "checkmark.circle.fill"
        case .problem: return "exclamationmark.triangle.fill"
        case .outcome: return "flag.checkered"
        }
    }

    private func color(_ kind: KaiAgentController.LineKind) -> Color {
        switch kind {
        case .performed: return .green
        case .problem: return .orange
        case .outcome: return .purple
        default: return .secondary
        }
    }
}
