//
//  KaiMailViewEditor.swift
//  Kai OS macOS
//
//  The small form for building a mail view by hand. A view is only a filter over the inbox shown on the Mail page:
//  it never changes mail. The same views can be made in chat ("show me unread mail from Dana").
//

import SwiftUI
import KaiLocalData

struct KaiMailViewEditor: View {
    var onSave: (KaiMailSavedView) throws -> Void
    var onCancel: () -> Void

    private enum Age: String, CaseIterable, Identifiable {
        case any = "Any time", today = "Last day", week = "Last 7 days", month = "Last 30 days", olderWeek = "Older than 7 days", olderMonth = "Older than 30 days"
        var id: String { rawValue }
        var limits: (older: Int, within: Int) {
            switch self {
            case .any: return (0, 0)
            case .today: return (0, 1)
            case .week: return (0, 7)
            case .month: return (0, 30)
            case .olderWeek: return (7, 0)
            case .olderMonth: return (30, 0)
            }
        }
    }

    @State private var name = ""
    @State private var sender = ""
    @State private var subject = ""
    @State private var unreadOnly = false
    @State private var flaggedOnly = false
    @State private var age = Age.any
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New mail view").font(.title3).fontWeight(.semibold)
            Text("Shows the messages in your inbox that match. It only filters what you see: nothing in Mail changes.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Name, for example Unread from Dana", text: $name).textFieldStyle(.roundedBorder)
            TextField("From (a name or an address)", text: $sender).textFieldStyle(.roundedBorder)
            TextField("Subject has", text: $subject).textFieldStyle(.roundedBorder)
            Toggle("Unread only", isOn: $unreadOnly)
            Toggle("Flagged only", isOn: $flaggedOnly)
            Picker("Received", selection: $age) { ForEach(Age.allCases) { Text($0.rawValue).tag($0) } }
            if let problem { Text(problem).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save view") {
                    let limits = age.limits
                    let view = KaiMailSavedView(name: name, senderContains: sender, subjectContains: subject, unreadOnly: unreadOnly,
                                                flaggedOnly: flaggedOnly, olderThanDays: limits.older, withinDays: limits.within)
                    do { try onSave(view) } catch { problem = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
