//
//  KaiSidekickSettings.swift
//  Kai OS macOS
//
//  Sidekick's settings: the shortcut key, notch clicks, custom instructions and speed. One view, shown
//  in Preferences and on the Sidekick page, so there is a single set of controls.
//

import KaiAgent
import KaiNotchCore
import KaiShared
import SwiftUI

struct KaiSidekickSettingsView: View {
    @AppStorage(KaiNotchPreferences.peeksKey) private var notchPeeks = false
    @AppStorage(KaiNotchPreferences.clickKey) private var clickOpens = true
    @AppStorage(KaiSharedKey.defaultsKey) private var sharedKey = KaiSharedKey.default.rawValue
    @AppStorage(KaiInstructions.defaultsKey) private var instructions = ""
    @AppStorage(KaiAgentEffort.defaultsKey) private var effort = KaiAgentEffort.default.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activation and notch").font(.title3).fontWeight(.semibold)
                VStack(spacing: 0) {
                    settingRow("Shared shortcut key", "Tap to open Kai, hold to talk, double tap to draft an email reply. Needs Accessibility permission.") {
                        Picker("", selection: $sharedKey) {
                            ForEach(KaiSharedKey.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    settingRow("Open Kai by clicking the notch", "Turn off to leave notch clicks to other apps. You can still open Kai with your shortcut key.") {
                        Toggle("", isOn: $clickOpens).labelsHidden().toggleStyle(.switch).tint(.green)
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    settingRow("Compact notch mode", "Keep a short status beside the notch while Kai works, and a peek when something finishes.") {
                        Toggle("", isOn: $notchPeeks).labelsHidden().toggleStyle(.switch).tint(.green)
                            .onChange(of: notchPeeks) { _, _ in KaiNotchWindowController.shared.preferencesChanged() }
                    }
                }
                .kaiGlassSurface(radius: 16)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Custom instructions").font(.title3).fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tell Kai how you like things done. It follows these in chat and in computer tasks, below its safety rules: they never turn off approval or make it trust text from the screen.")
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $instructions)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14))
                            .padding(8)
                            .frame(height: 120)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.5)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            .onChange(of: instructions) { _, value in
                                if value.count > KaiInstructions.maxLength { instructions = String(value.prefix(KaiInstructions.maxLength)) }
                            }
                        if instructions.isEmpty {
                            Text("Use Slack for work messages and Safari for browsing.")
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.horizontal, 14).padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    Text("\(instructions.count) of \(KaiInstructions.maxLength) characters. Kept on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                .kaiGlassSurface(radius: 16)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Speed & intelligence").font(.title3).fontWeight(.semibold)
                Text("Choose how much thought goes into computer tasks.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    Slider(value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 0...2, step: 1)
                        .tint(Color(red: 0.55, green: 0.35, blue: 0.9))
                    HStack {
                        ForEach(KaiAgentEffort.allCases, id: \.rawValue) { level in
                            Text(level.title)
                                .font(.callout).fontWeight(effort == level.rawValue ? .semibold : .regular)
                                .foregroundStyle(effort == level.rawValue ? Color.white : Color.secondary)
                                .frame(maxWidth: .infinity, alignment: level.rawValue == 0 ? .leading : (level.rawValue == 2 ? .trailing : .center))
                        }
                    }
                    Text((KaiAgentEffort(rawValue: effort) ?? .default).detail).font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                .kaiGlassSurface(radius: 16)
            }
        }
    }


    /// A row in a grouped card: a title and a description on the left, the control on the right.
    private func settingRow<Control: View>(_ title: String, _ detail: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }
}
