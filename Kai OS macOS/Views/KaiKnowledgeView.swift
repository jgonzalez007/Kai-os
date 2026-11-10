//
//  KaiKnowledgeView.swift
//  Kai OS macOS
//
//  What Kai knows, to look at: a list of notes with a reader, and a graph where related things are joined.
//  It reads the same local database that chat searches. Nothing here leaves the Mac.
//

import AppKit
import KaiKnowledge
import SwiftUI

struct KaiKnowledgeView: View {
    @EnvironmentObject var appState: AppState

    private enum Mode: String, CaseIterable { case about = "About you", graph = "Graph", notes = "Notes" }

    /// Set by the snapshot harness, to draw the graph face.
    static var startInGraph = false
    @State private var mode = Mode.about
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var hiddenSources: Set<String> = []
    @State private var hideIsolated = false
    @State private var documents: [KaiKnowledgeDocument] = []
    @State private var graph = KaiKnowledgeGraph(nodes: [], edges: [])
    @State private var loading = true
    @State private var selectedID: String?
    @State private var hoverID: String?
    @State private var query = ""
    @State private var hits: [KaiKnowledgeHit]?

    private func key(_ d: KaiKnowledgeDocument) -> String { d.source + "|" + d.sourceID }
    private var selected: KaiKnowledgeDocument? { documents.first { key($0) == selectedID } }

    var body: some View {
        VStack(spacing: 14) {
            header
            if loading {
                ProgressView("Reading your knowledge base…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mode == .about {
                KaiAboutYouView(cards: appState.morningCards, documentCount: documents.count)
            } else if documents.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    if mode == .graph { graphPane } else { listPane }
                    if selected != nil || mode == .notes { readerPane.frame(width: mode == .graph ? 340 : nil) }
                }
            }
        }
        .padding(.horizontal, 28).padding(.bottom, 24)
        .task { if Self.startInGraph { mode = .graph }; await load() }
        // A file or folder added in setup, or a fresh Index now, shows up here without leaving the page.
        .onChange(of: appState.knowledgeCounts) { _, _ in Task { await load() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Knowledge").font(.system(size: 26, weight: .semibold))
                Text(loading ? "" : "\(documents.count) documents · \(graph.edges.count) connections")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
            TextField("Search what Kai knows", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(width: 220)
                .background(Capsule().fill(Color.white.opacity(0.07)))
                .onSubmit { runSearch() }
                .onChange(of: query) { _, value in if value.isEmpty { hits = nil } }
            Button { appState.openPreferences(.knowledge) } label: { Label("Add a note", systemImage: "plus") }
                .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            KaiLogoMark(size: 60)
            Text("Nothing here yet").font(.title3).fontWeight(.semibold)
            Text("Kai fills this from your knowledge folder, Notes, Calendar, Mail and Slack, and from notes you type in. Add a note, or index what is connected.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button("Add a note") { appState.openPreferences(.knowledge) }.buttonStyle(.borderedProminent).tint(KaiColor.liquidBlue)
                Button("Index now") { Task { _ = await appState.indexKnowledgeNow(); await load() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Notes

    private var listPane: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if let hits {
                    if hits.isEmpty { Text("Nothing matched.").foregroundStyle(.secondary).padding(.top, 20) }
                    ForEach(hits.indices, id: \.self) { index in
                        let hit = hits[index]
                        row(title: hit.title, detail: hit.snippet, source: hit.source, id: hit.source + "|" + hit.sourceID)
                    }
                } else {
                    ForEach(documents.indices, id: \.self) { index in
                        let d = documents[index]
                        row(title: d.title, detail: String(d.text.prefix(110)).replacingOccurrences(of: "\n", with: " "), source: d.source, id: key(d))
                    }
                }
            }
        }
        .frame(width: 340)
    }

    private func row(title: String, detail: String, source: String, id: String) -> some View {
        Button { selectedID = id } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(Self.color(for: source)).frame(width: 8, height: 8).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(selectedID == id ? 0.12 : 0.04)))
        }
        .buttonStyle(.plain)
    }

    private var readerPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let doc = selected {
                HStack {
                    Circle().fill(Self.color(for: doc.source)).frame(width: 9, height: 9)
                    Text(Self.label(for: doc.source)).font(.caption).foregroundStyle(.secondary)
                    if let modified = doc.modified { Text("· " + modified.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if doc.source == KaiKnowledgeIndexer.folderSource {
                        Button("Open file") { NSWorkspace.shared.open(appState.knowledgeFolder.appendingPathComponent(doc.sourceID)) }.controlSize(.small)
                    }
                    Button { selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                Text(doc.title).font(.system(size: 20, weight: .semibold))
                ScrollView {
                    Text(rendered(doc.text)).font(.system(size: 14)).lineSpacing(4)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                let related = relatedDocuments(of: doc)
                if !related.isEmpty {
                    Divider().overlay(Color.white.opacity(0.1))
                    Text("Connected to").font(.caption).foregroundStyle(.secondary)
                    ForEach(related.prefix(5), id: \.self) { id in
                        if let other = documents.first(where: { key($0) == id }) {
                            Button { selectedID = id } label: {
                                Label(other.title, systemImage: "link").font(.callout).lineLimit(1)
                            }
                            .buttonStyle(.plain).foregroundStyle(KaiColor.cyan)
                        }
                    }
                }
            } else {
                Text("Choose something on the left to read it.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kaiLiquidGlass(KaiColor.cyan, radius: 18, glow: 0.1)
    }

    private func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func relatedDocuments(of doc: KaiKnowledgeDocument) -> [String] {
        guard let index = graph.nodes.first(where: { $0.id == key(doc) })?.index else { return [] }
        return graph.edges.filter { $0.a == index || $0.b == index }
            .sorted { $0.weight > $1.weight }
            .map { graph.nodes[$0.a == index ? $0.b : $0.a].id }
    }

    // MARK: Graph

    private var graphPane: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                Canvas { context, size in draw(&context, size) }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in selectedID = nearest(to: tap.location, in: geo.size)?.id })
                    .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { value in
                        pan = CGSize(width: panStart.width + value.translation.width, height: panStart.height + value.translation.height)
                    }.onEnded { _ in panStart = pan })
                    .simultaneousGesture(MagnifyGesture().onChanged { value in
                        scale = min(max(scaleStart * value.magnification, 0.6), 6)
                    }.onEnded { _ in scaleStart = scale })
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point): hoverID = nearest(to: point, in: geo.size)?.id
                        case .ended: hoverID = nil
                        }
                    }
                    .overlay(alignment: .topTrailing) { zoomControls.padding(10) }
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            legend
        }
    }

    @State private var panStart: CGSize = .zero
    @State private var scaleStart: CGFloat = 1

    private var zoomControls: some View {
        VStack(spacing: 6) {
            Button { zoom(1.4) } label: { Image(systemName: "plus") }
            Button { zoom(1 / 1.4) } label: { Image(systemName: "minus") }
            Button { scale = 1; scaleStart = 1; pan = .zero; panStart = .zero } label: { Image(systemName: "scope") }.help("Fit everything")
        }
        .buttonStyle(.plain).padding(6)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }

    private func zoom(_ factor: CGFloat) {
        scale = min(max(scale * factor, 0.6), 6); scaleStart = scale
    }

    /// A dot shows unless its source is switched off, or it joins nothing and isolated ones are hidden.
    private func isVisible(_ node: KaiGraphNode) -> Bool {
        !hiddenSources.contains(node.source) && !(hideIsolated && node.degree == 0)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            ForEach(Array(Set(graph.nodes.map(\.source))).sorted(), id: \.self) { source in
                let off = hiddenSources.contains(source)
                Button {
                    if off { hiddenSources.remove(source) } else { hiddenSources.insert(source) }
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(Self.color(for: source)).frame(width: 8, height: 8)
                        Text(Self.label(for: source)).font(.caption)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(off ? 0.02 : 0.08)))
                    .opacity(off ? 0.4 : 1)
                }
                .buttonStyle(.plain).help(off ? "Show \(Self.label(for: source))" : "Hide \(Self.label(for: source))")
            }
            Toggle("Hide unconnected", isOn: $hideIsolated).toggleStyle(.checkbox).font(.caption)
            Spacer()
            Text("Drag to move, pinch or use + and − to zoom. Click a dot to read it. Ringed dots are notes you wrote for Kai.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func point(_ node: KaiGraphNode, _ size: CGSize) -> CGPoint {
        let base = CGPoint(x: 24 + node.x * (size.width - 48), y: 24 + node.y * (size.height - 48))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: center.x + (base.x - center.x) * scale + pan.width, y: center.y + (base.y - center.y) * scale + pan.height)
    }

    private func nearest(to location: CGPoint, in size: CGSize) -> KaiGraphNode? {
        graph.nodes.filter(isVisible).map { ($0, hypot(point($0, size).x - location.x, point($0, size).y - location.y)) }
            .filter { $0.1 <= 16 }.min { $0.1 < $1.1 }?.0
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        // A name on the best-connected dot of each cluster only (daily digests of one channel share a name),
        // so the picture does not fill up with overlapping words.
        var best: [String: KaiGraphNode] = [:]
        for node in graph.nodes where node.degree >= 2 && isVisible(node) {
            let group = node.title.components(separatedBy: " — ").first ?? node.title
            if let current = best[group], current.degree >= node.degree { continue }
            best[group] = node
        }
        let labelled = Set(best.values.sorted { $0.degree > $1.degree }.prefix(scale > 1.8 ? 24 : 8).map(\.id))
        var placed: [CGRect] = []
        let focus = hoverID ?? selectedID
        let focusIndex = graph.nodes.first { $0.id == focus }?.index
        for edge in graph.edges where isVisible(graph.nodes[edge.a]) && isVisible(graph.nodes[edge.b]) {
            var path = Path()
            path.move(to: point(graph.nodes[edge.a], size))
            path.addLine(to: point(graph.nodes[edge.b], size))
            let near = focusIndex != nil && (edge.a == focusIndex || edge.b == focusIndex)
            context.stroke(path, with: .color(near ? KaiColor.cyan.opacity(0.9) : Color.white.opacity(0.10 + 0.25 * edge.weight)), lineWidth: near ? 1.6 : 0.8)
        }
        for node in graph.nodes where isVisible(node) {
            let center = point(node, size)
            let radius = (4.5 + min(Double(node.degree), 6) * 1.2) * min(max(Double(scale), 0.8), 1.8)
            let isFocus = node.id == focus
            let isNeighbor = focusIndex != nil && graph.edges.contains { ($0.a == focusIndex && $0.b == node.index) || ($0.b == focusIndex && $0.a == node.index) }
            let color = Self.color(for: node.source)
            if isFocus || node.id == selectedID {
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius - 6, y: center.y - radius - 6, width: (radius + 6) * 2, height: (radius + 6) * 2)), with: .color(color.opacity(0.25)))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(focusIndex != nil && !isFocus && !isNeighbor ? color.opacity(0.35) : color))
            if node.sourceID.hasPrefix(KaiManualNote.folderName + "/") {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - radius - 3, y: center.y - radius - 3, width: (radius + 3) * 2, height: (radius + 3) * 2)), with: .color(.white.opacity(0.85)), lineWidth: 1.4)
            }
            if isFocus || isNeighbor || labelled.contains(node.id) {
                let shown = node.title.count > 28 ? String(node.title.prefix(28)) + "…" : node.title
                let at = CGPoint(x: center.x, y: center.y + radius + 9)
                let box = CGRect(x: at.x - Double(shown.count) * 2.9, y: at.y - 7, width: Double(shown.count) * 5.8, height: 14)
                // A name that would sit on top of another is left out, unless it is the one being looked at.
                if isFocus || !placed.contains(where: { $0.intersects(box) }) {
                    placed.append(box)
                    let text = Text(shown)
                        .font(.system(size: isFocus ? 12 : 10, weight: isFocus ? .semibold : .regular)).foregroundColor(.white.opacity(isFocus ? 1 : 0.7))
                    context.draw(text, at: at)
                }
            }
        }
    }

    // MARK: Loading and searching

    private func load() async {
        loading = true
        let result: (docs: [KaiKnowledgeDocument], graph: KaiKnowledgeGraph)? = await Task.detached {
            guard let store = await appState.openKnowledgeStore(), let docs = try? store.balancedDocuments(perSource: 60) else { return nil }
            return (docs, KaiKnowledgeGraph.build(documents: docs))
        }.value
        documents = result?.docs ?? []
        graph = result?.graph ?? KaiKnowledgeGraph(nodes: [], edges: [])
        loading = false
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let store = appState.openKnowledgeStore() else { hits = nil; return }
        hits = (try? store.search(q, limit: 30)) ?? []
        mode = .notes
    }

    static func color(for source: String) -> Color {
        switch source {
        case KaiKnowledgeIndexer.folderSource, KaiKnowledgeIndexer.extraFoldersSource, KaiKnowledgeIndexer.referenceSource: return KaiColor.cyan
        case KaiKnowledgeIndexer.notesSource: return Color(red: 1.0, green: 0.8, blue: 0.25)
        case KaiKnowledgeIndexer.calendarSource: return Color(red: 1.0, green: 0.38, blue: 0.35)
        case KaiKnowledgeIndexer.mailSource: return KaiColor.liquidBlue
        case "slack": return Color(red: 0.66, green: 0.50, blue: 1.0)
        default: return .white.opacity(0.7)
        }
    }

    static func label(for source: String) -> String {
        switch source {
        case KaiKnowledgeIndexer.folderSource: return "Files"
        case KaiKnowledgeIndexer.extraFoldersSource: return "Folders"
        case KaiKnowledgeIndexer.referenceSource: return "Reference"
        case KaiKnowledgeIndexer.notesSource: return "Notes"
        case KaiKnowledgeIndexer.calendarSource: return "Calendar"
        case KaiKnowledgeIndexer.mailSource: return "Mail"
        case "slack": return "Slack"
        default: return source.capitalized
        }
    }
}
