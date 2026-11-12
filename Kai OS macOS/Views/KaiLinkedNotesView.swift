//
//  KaiLinkedNotesView.swift
//  Kai OS macOS
//
//  The linked notes Kai wrote, as a constellation (a dot per note, a thread per link) and as a reader. They are
//  ordinary Markdown files in ~/Kai OS - Linked Notes: read them, edit them, add your own, in Kai or any editor.
//  Kai never rewrites a note you changed.
//

import AppKit
import KaiKnowledge
import SwiftUI

struct KaiLinkedNotesView: View {
    @EnvironmentObject var appState: AppState

    private struct Note: Identifiable, Hashable { let path: String; let title: String; var id: String { path } }

    @State private var notes: [Note] = []
    @State private var selected: String?
    @State private var text = ""
    @State private var editing = false
    @State private var draft = ""
    @State private var showSky = true
    @State private var graph = KaiKnowledgeGraph()
    @State private var hoverID: String?
    @State private var newName = ""
    @State private var adding = false
    @State private var trail: [String] = []
    @State private var problem: String?

    private var vault: URL { appState.linkedNotesURL }

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if notes.isEmpty { emptyState } else {
                HStack(alignment: .top, spacing: 14) {
                    sidebar.frame(width: 250)
                    if showSky && selected == nil { sky } else { reader }
                }
            }
        }
        .task { reload() }
        .onChange(of: appState.notesRevision) { _, _ in reload() }
    }

    // MARK: Top bar

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(notes.isEmpty ? "No notes yet" : "\(notes.count) notes · \(graph.edges.count) links").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if appState.isTriaging || appState.isBuildingNotes {
                    ProgressView().controlSize(.small)
                    Button("Stop") { appState.cancelKnowledgeWork() }.controlSize(.small)
                } else {
                    Button { appState.startSummarizing() } label: { Label("Read new items (\(appState.summaryCounts.pending))", systemImage: "text.magnifyingglass") }
                        .controlSize(.small).disabled(appState.summaryCounts.pending == 0)
                    Button { appState.startBuildingNotes() } label: { Label(notes.isEmpty ? "Write notes" : "Update notes", systemImage: "sparkles") }
                        .controlSize(.small).kaiProminent().disabled(appState.summaryCounts.survivors < 5)
                }
                if !notes.isEmpty {
                    Button { selected = nil; editing = false; showSky = true } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }
                        .controlSize(.small).help("Show the constellation")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([vault]) } label: { Image(systemName: "folder") }
                        .controlSize(.small).help("Show in Finder")
                }
            }
            Text(statusLine).font(.caption).foregroundStyle(.secondary)
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { appState.refreshSummaryCounts() }
    }

    private var statusLine: String {
        if let message = appState.knowledgeWorkMessage, appState.isTriaging || appState.isBuildingNotes || !message.isEmpty { return message }
        let c = appState.summaryCounts
        return "\(c.survivors) items kept as summaries, \(c.junk + c.sensitive) skipped (junk or private), \(c.pending) waiting. Everything runs on this Mac."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            KaiLogoMark(size: 56)
            Text("Linked notes").font(.title3).fontWeight(.semibold)
            Text("Kai reads each item in your knowledge base into a short summary, drops junk and anything private, then writes notes about the people, projects and commitments it finds, linked to each other. Everything stays on this Mac.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
            Text("1. Read new items.  2. Write notes.").font(.callout)
            if appState.summaryCounts.survivors < 5 && appState.summaryCounts.pending == 0 {
                Text("Index your sources first, on the Knowledge setup page.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if notes.contains(where: { $0.path == KaiVault.overviewName }) { noteButton(Note(path: KaiVault.overviewName, title: "Overview"), icon: "book") }
                ForEach(folders, id: \.self) { folder in
                    Text(folder).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    ForEach(notes.filter { folderOf($0) == folder }) { noteButton($0, icon: "doc.text") }
                }
                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 6)
                if adding {
                    TextField("Note name", text: $newName).textFieldStyle(.roundedBorder).onSubmit(createNote)
                } else {
                    Button { adding = true } label: { Label("New note", systemImage: "plus") }.controlSize(.small)
                }
            }
        }
    }

    private var folders: [String] {
        let order = KaiNoteKind.allCases.map(\.folder)
        return Set(notes.filter { $0.path != KaiVault.overviewName }.map(folderOf)).sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    private func folderOf(_ note: Note) -> String { note.path.split(separator: "/").count > 1 ? String(note.path.split(separator: "/")[0]) : "Other" }

    private func noteButton(_ note: Note, icon: String) -> some View {
        Button { open(note.path, pushing: true) } label: {
            Label(note.title, systemImage: icon).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected == note.path ? 0.12 : 0)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Reader and editor

    private var reader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { back() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).disabled(trail.count < 2 && !showSky)
                Spacer()
                if editing {
                    Button("Cancel") { editing = false }.controlSize(.small)
                    Button("Save") { save() }.controlSize(.small).kaiProminent()
                } else if selected != nil {
                    Button("Edit") { draft = text; editing = true }.controlSize(.small)
                    if selected != KaiVault.overviewName {
                        Button { trash() } label: { Image(systemName: "trash") }.controlSize(.small).help("Move to the Trash")
                    }
                }
            }
            if editing {
                TextEditor(text: $draft).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            } else if selected != nil {
                ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(Array(blocks(text).enumerated()), id: \.offset) { $0.element } }.frame(maxWidth: .infinity, alignment: .leading) }
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "kai-note", let title = url.host(percentEncoded: false) ?? url.absoluteString.split(separator: "/").last.map(String.init),
                              let note = notes.first(where: { KaiVault.normalized($0.title) == KaiVault.normalized(title) }) else { return .discarded }
                        open(note.path, pushing: true)
                        return .handled
                    })
            } else {
                Text("Choose a note on the left.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.1)
    }

    /// Headings, bullets and paragraphs, with [[links]] made clickable when the note exists.
    private func blocks(_ markdown: String) -> [AnyView] {
        markdown.components(separatedBy: "\n").map { raw -> AnyView in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return AnyView(Spacer().frame(height: 2)) }
            var level = 0
            while level < 3, line.hasPrefix(String(repeating: "#", count: level + 1) + " ") { level += 1 }
            let body = level > 0 ? String(line.dropFirst(level + 1)) : (line.hasPrefix("- ") || line.hasPrefix("* ") ? "•  " + line.dropFirst(2) : line)
            let font: Font = level == 1 ? .system(size: 22, weight: .semibold) : level == 2 ? .system(size: 17, weight: .semibold) : level == 3 ? .system(size: 15, weight: .semibold) : .system(size: 14)
            return AnyView(Text(linked(body)).font(font).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading))
        }
    }

    private func linked(_ text: String) -> AttributedString {
        let pattern = try? NSRegularExpression(pattern: "\\[\\[([^\\]|#]+)(?:#[^\\]|]*)?(?:\\|([^\\]]+))?\\]\\]")
        var result = text
        for match in (pattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).reversed() {
            guard let whole = Range(match.range, in: result), let titleRange = Range(match.range(at: 1), in: result) else { continue }
            let title = String(result[titleRange]).trimmingCharacters(in: .whitespaces)
            let shown = Range(match.range(at: 2), in: result).map { String(result[$0]) } ?? title
            let exists = notes.contains { KaiVault.normalized($0.title) == KaiVault.normalized(title) }
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? title
            result.replaceSubrange(whole, with: exists ? "[\(shown)](kai-note://\(encoded))" : shown)
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: result, options: options)) ?? AttributedString(result)
    }

    // MARK: Constellation

    private var sky: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                Canvas { context, size in draw(&context, size) }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in if let node = nearest(to: tap.location, in: geo.size) { open(node.sourceID, pushing: true) } })
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hoverID = nearest(to: point, in: geo.size)?.id
                        case .ended: hoverID = nil
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            HStack(spacing: 12) {
                ForEach(KaiNoteKind.allCases, id: \.self) { kind in
                    HStack(spacing: 5) { Circle().fill(Self.color(forFolder: kind.folder)).frame(width: 8, height: 8); Text(kind.folder).font(.caption) }
                }
                Spacer()
                Text("Click a dot to read it. Bigger dots have more links.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The dots are spread to fill the sky: the layout leaves unconnected groups far apart in a corner.
    private func point(_ node: KaiGraphNode, _ size: CGSize) -> CGPoint {
        let xs = graph.nodes.map(\.x), ys = graph.nodes.map(\.y)
        let (minX, maxX, minY, maxY) = (xs.min() ?? 0, xs.max() ?? 1, ys.min() ?? 0, ys.max() ?? 1)
        let fx = maxX > minX ? (node.x - minX) / (maxX - minX) : 0.5
        let fy = maxY > minY ? (node.y - minY) / (maxY - minY) : 0.5
        return CGPoint(x: 50 + fx * (size.width - 100), y: 40 + fy * (size.height - 80))
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> KaiGraphNode? {
        graph.nodes.map { ($0, hypot(point($0, size).x - location.x, point($0, size).y - location.y)) }.filter { $0.1 <= 18 }.min { $0.1 < $1.1 }?.0
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let focusIndex = graph.nodes.first { $0.id == hoverID }?.index
        for edge in graph.edges {
            var path = Path()
            path.move(to: point(graph.nodes[edge.a], size)); path.addLine(to: point(graph.nodes[edge.b], size))
            let near = focusIndex != nil && (edge.a == focusIndex || edge.b == focusIndex)
            context.stroke(path, with: .color(near ? KaiColor.cyan.opacity(0.9) : Color.white.opacity(0.16)), lineWidth: near ? 1.6 : 0.8)
        }
        var placed: [CGRect] = []
        for node in graph.nodes.sorted(by: { $0.degree > $1.degree }) {
            let center = point(node, size)
            let radius = 4.5 + min(Double(node.degree), 8) * 1.3
            let color = Self.color(forFolder: node.sourceID.split(separator: "/").first.map(String.init) ?? "")
            let isFocus = node.id == hoverID
            if isFocus { context.fill(Path(ellipseIn: CGRect(x: center.x - radius - 7, y: center.y - radius - 7, width: (radius + 7) * 2, height: (radius + 7) * 2)), with: .color(color.opacity(0.25))) }
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
            let shown = node.title.count > 26 ? String(node.title.prefix(26)) + "…" : node.title
            let box = CGRect(x: center.x - Double(shown.count) * 2.9, y: center.y + radius + 2, width: Double(shown.count) * 5.8, height: 14)
            if isFocus || (node.degree >= 1 && !placed.contains(where: { $0.intersects(box) })) {
                placed.append(box)
                context.draw(Text(shown).font(.system(size: isFocus ? 12 : 10, weight: isFocus ? .semibold : .regular)).foregroundColor(.white.opacity(isFocus ? 1 : 0.75)), at: CGPoint(x: center.x, y: center.y + radius + 9))
            }
        }
    }

    static func color(forFolder folder: String) -> Color {
        switch folder {
        case "People": return KaiColor.cyan
        case "Projects": return KaiColor.liquidBlue
        case "Commitments": return Color(red: 1.0, green: 0.62, blue: 0.3)
        case "Topics": return Color(red: 0.66, green: 0.50, blue: 1.0)
        default: return .white.opacity(0.7)
        }
    }

    // MARK: Actions

    private func reload() {
        let found = KaiVault.notes(in: vault).map { Note(path: $0.path, title: $0.title) }
        notes = found
        graph = found.isEmpty ? KaiKnowledgeGraph() : KaiVaultIndex.graph(vault: vault)
        if let selected, !found.contains(where: { $0.path == selected }) { self.selected = nil }
        if let selected { text = read(selected) }
    }

    private func read(_ path: String) -> String {
        (try? String(contentsOf: vault.resolvingSymlinksInPath().appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    private func open(_ path: String, pushing: Bool) {
        guard !editing else { problem = "Save or cancel your edit first."; return }
        problem = nil
        selected = path
        text = read(path)
        if pushing { trail.append(path) }
    }

    private func back() {
        if trail.count >= 2 { trail.removeLast(); open(trail.last ?? "", pushing: false) } else { selected = nil; trail = [] }
    }

    private func save() {
        guard let selected else { return }
        do {
            try Data(draft.utf8).write(to: vault.resolvingSymlinksInPath().appendingPathComponent(selected), options: [.atomic])
            text = draft; editing = false; problem = nil
            reload()
        } catch { problem = "Couldn't save: \(error.localizedDescription)" }
    }

    private func trash() {
        guard let selected else { return }
        do {
            try FileManager.default.trashItem(at: vault.resolvingSymlinksInPath().appendingPathComponent(selected), resultingItemURL: nil)
            self.selected = nil; trail = []
            reload()
        } catch { problem = "Couldn't move it to the Trash: \(error.localizedDescription)" }
    }

    private func createNote() {
        guard let title = KaiVault.cleanTitle(newName) else { problem = "Use a plain name, 2 to 60 characters, without slashes or brackets."; return }
        let path = "Topics/" + KaiVault.fileName(for: title)
        let url = vault.resolvingSymlinksInPath().appendingPathComponent(path)
        guard !FileManager.default.fileExists(atPath: url.path) else { problem = "A note with that name exists."; return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# \(title)\n\n".utf8).write(to: url, options: [.atomic])
            newName = ""; adding = false; problem = nil
            reload()
            open(path, pushing: true)
            draft = text; editing = true
        } catch { problem = "Couldn't make the note: \(error.localizedDescription)" }
    }
}
