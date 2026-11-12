//
//  KaiMemoryCard.swift
//  Kai OS macOS
//
//  What Kai remembers about you between chats. You can write notes here, and the chat adds one only when you ask it
//  to remember something. Each note can be edited, turned off or deleted. Notes stay on this Mac and are used as
//  background in the chat, on a local model or on Claude.
//

import KaiShared
import SwiftUI

struct KaiMemoryCard: View {
    @State private var notes: [KaiMemoryNote] = KaiMemoryStore.standard.load()
    @State private var draft = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What Kai remembers").font(.title3).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 12) {
                Text("Short notes about you, used as background in every chat: how you like answers, who you work with, what you are working on. Ask in a chat (“remember that I prefer bullet points”) or write one here. They are kept on this Mac. With Claude as the chat model they are sent along with your questions.")
                    .font(.callout)
                HStack {
                    TextField("Add a note, for example: I work at SailPoint and prefer short answers", text: $draft).textFieldStyle(.roundedBorder).onSubmit(add)
                    Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
                if notes.isEmpty { Text("Nothing remembered yet.").font(.callout).foregroundStyle(.secondary) }
                ForEach(notes) { note in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { note.enabled }, set: { setEnabled(note.id, $0) })).labelsHidden().kaiSwitch().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("", text: Binding(get: { note.text }, set: { edit(note.id, $0) })).textFieldStyle(.plain)
                                .foregroundStyle(note.enabled ? Color.primary : Color.secondary)
                            if note.fromChat { Text("Added from a chat").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button { notes.removeAll { $0.id == note.id }; persist() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete this note")
                    }
                }
                if !notes.isEmpty { Button("Forget everything") { notes = []; persist() }.controlSize(.small) }
            }
            .padding(20)
            .kaiGlassSurface(radius: 16)
        }
        .onAppear { notes = KaiMemoryStore.standard.load() }
    }

    private func add() {
        guard let clean = KaiMemory.sanitize(draft) else {
            problem = "That can't be kept: it is too short, or it looks like a password, code, web address or instruction. Write a plain fact about you."
            return
        }
        problem = nil
        notes = KaiMemory.merge([KaiMemoryNote(text: clean)], into: notes)
        draft = ""
        persist()
    }

    private func edit(_ id: String, _ text: String) {
        // Typing is kept as it comes; it is cleaned when saved, and a note that fails the check is not saved.
        notes = notes.map { var n = $0; if n.id == id { n.text = String(text.prefix(KaiMemory.maxLength)) }; return n }
        persist()
    }

    private func persist() {
        let kept = notes.compactMap { note -> KaiMemoryNote? in
            guard let clean = KaiMemory.sanitize(note.text) else { return nil }
            var copy = note; copy.text = clean; return copy
        }
        try? KaiMemoryStore.standard.save(kept)
    }

    private func setEnabled(_ id: String, _ on: Bool) {
        notes = notes.map { var n = $0; if n.id == id { n.enabled = on }; return n }
        persist()
    }
}
