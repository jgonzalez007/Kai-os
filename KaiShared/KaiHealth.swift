import Foundation

public struct KaiHealthItem: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable { case ok, attention, off }

    public let id: String
    public let title: String
    public let status: Status
    public let detail: String

    public init(id: String, title: String, status: Status, detail: String) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

/// What the Health pane reads. Plain values, so the pane's logic can be tested.
public struct KaiHealthInputs: Equatable, Sendable {
    /// nil means Ollama could not be reached.
    public var ollamaModels: [String]?
    public var selectedModel: String
    public var permissionsMissing: Int
    public var calendarConnected: Bool
    public var mailConnected: Bool
    public var notesConnected: Bool
    public var useCloud: Bool
    public var hasOpenAIKey: Bool
    public var hasAnthropicKey: Bool
    public var briefingCardCount: Int
    public var briefingError: String?
    public var briefingIsRunning: Bool
    public var knowledgeDocuments: Int
    public var nightShift: KaiNightShiftSettings
    public var nightShiftRecord: KaiNightShiftRecord?

    public init(
        ollamaModels: [String]? = nil, selectedModel: String = "", permissionsMissing: Int = 0,
        calendarConnected: Bool = false, mailConnected: Bool = false, notesConnected: Bool = false,
        useCloud: Bool = false, hasOpenAIKey: Bool = false, hasAnthropicKey: Bool = false,
        briefingCardCount: Int = 0, briefingError: String? = nil, briefingIsRunning: Bool = false,
        knowledgeDocuments: Int = 0, nightShift: KaiNightShiftSettings = KaiNightShiftSettings(),
        nightShiftRecord: KaiNightShiftRecord? = nil
    ) {
        self.ollamaModels = ollamaModels
        self.selectedModel = selectedModel
        self.permissionsMissing = permissionsMissing
        self.calendarConnected = calendarConnected
        self.mailConnected = mailConnected
        self.notesConnected = notesConnected
        self.useCloud = useCloud
        self.hasOpenAIKey = hasOpenAIKey
        self.hasAnthropicKey = hasAnthropicKey
        self.briefingCardCount = briefingCardCount
        self.briefingError = briefingError
        self.briefingIsRunning = briefingIsRunning
        self.knowledgeDocuments = knowledgeDocuments
        self.nightShift = nightShift
        self.nightShiftRecord = nightShiftRecord
    }
}

public enum KaiHealth {
    public static func items(_ input: KaiHealthInputs) -> [KaiHealthItem] {
        [local(input), cloud(input), permissions(input), sources(input), knowledge(input), nightShift(input), briefing(input)]
    }

    private static func local(_ i: KaiHealthInputs) -> KaiHealthItem {
        guard let models = i.ollamaModels else {
            return KaiHealthItem(id: "ollama", title: "Local model", status: .attention,
                                 detail: "Ollama is not reachable at localhost:11434. Start it to chat locally.")
        }
        guard !models.isEmpty else {
            return KaiHealthItem(id: "ollama", title: "Local model", status: .attention,
                                 detail: "Ollama is running but has no models. Run: ollama pull gemma4:e4b")
        }
        let name = KaiModelTag.name(from: i.selectedModel)
        let using = name.isEmpty ? "" : " Using \(name)."
        return KaiHealthItem(id: "ollama", title: "Local model", status: .ok,
                             detail: "\(models.count) model\(models.count == 1 ? "" : "s") available.\(using)")
    }

    private static func cloud(_ i: KaiHealthInputs) -> KaiHealthItem {
        var keys: [String] = []
        if i.hasOpenAIKey { keys.append("OpenAI") }
        if i.hasAnthropicKey { keys.append("Anthropic") }
        switch (i.useCloud, keys.isEmpty) {
        case (false, _):
            return KaiHealthItem(id: "cloud", title: "Cloud AI", status: .off,
                                 detail: keys.isEmpty ? "Off. Chat stays on this Mac." : "Off. Keys stored for \(keys.joined(separator: " and ")).")
        case (true, true):
            return KaiHealthItem(id: "cloud", title: "Cloud AI", status: .attention,
                                 detail: "On, but no API key is stored. Add one in Settings.")
        case (true, false):
            return KaiHealthItem(id: "cloud", title: "Cloud AI", status: .ok,
                                 detail: "On. Messages go to your provider. Keys stored for \(keys.joined(separator: " and ")).")
        }
    }

    private static func permissions(_ i: KaiHealthInputs) -> KaiHealthItem {
        i.permissionsMissing == 0
            ? KaiHealthItem(id: "permissions", title: "Permissions", status: .ok, detail: "All permissions are granted.")
            : KaiHealthItem(id: "permissions", title: "Permissions", status: .attention,
                            detail: "\(i.permissionsMissing) not granted yet. Open Permissions in the sidebar.")
    }

    private static func sources(_ i: KaiHealthInputs) -> KaiHealthItem {
        let connected = [("Calendar", i.calendarConnected), ("Mail", i.mailConnected), ("Notes", i.notesConnected)]
            .filter(\.1).map(\.0)
        return connected.isEmpty
            ? KaiHealthItem(id: "sources", title: "Sources", status: .off, detail: "Nothing connected. Connect Calendar, Mail or Notes from their pages.")
            : KaiHealthItem(id: "sources", title: "Sources", status: .ok, detail: "Connected: \(connected.joined(separator: ", ")).")
    }

    private static func knowledge(_ i: KaiHealthInputs) -> KaiHealthItem {
        i.knowledgeDocuments > 0
            ? KaiHealthItem(id: "knowledge", title: "Knowledge base", status: .ok,
                            detail: "\(i.knowledgeDocuments) document\(i.knowledgeDocuments == 1 ? "" : "s") indexed.")
            : KaiHealthItem(id: "knowledge", title: "Knowledge base", status: .off,
                            detail: "Empty. Click Index now under Knowledge base in Settings.")
    }

    public static func clock(hour: Int, minute: Int) -> String {
        String(format: "%d:%02d %@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "AM" : "PM")
    }

    private static func nightShift(_ i: KaiHealthInputs) -> KaiHealthItem {
        guard i.nightShift.enabled else {
            return KaiHealthItem(id: "nightshift", title: "Night Shift", status: .off, detail: "Off. Turn it on in Settings to prepare things overnight.")
        }
        let at = "Scheduled for \(clock(hour: i.nightShift.hour, minute: i.nightShift.minute))."
        guard let record = i.nightShiftRecord else {
            return KaiHealthItem(id: "nightshift", title: "Night Shift", status: .ok, detail: "\(at) It hasn't run yet.")
        }
        switch record.outcome {
        case .failed: return KaiHealthItem(id: "nightshift", title: "Night Shift", status: .attention, detail: "\(at) Last run: \(record.summary)")
        case .skipped, .completed: return KaiHealthItem(id: "nightshift", title: "Night Shift", status: .ok, detail: "\(at) Last run: \(record.summary)")
        }
    }

    private static func briefing(_ i: KaiHealthInputs) -> KaiHealthItem {
        if i.briefingIsRunning {
            return KaiHealthItem(id: "briefing", title: "Morning briefing", status: .ok, detail: "Running now.")
        }
        if let error = i.briefingError {
            return KaiHealthItem(id: "briefing", title: "Morning briefing", status: .attention, detail: error)
        }
        return KaiHealthItem(id: "briefing", title: "Morning briefing", status: i.briefingCardCount > 0 ? .ok : .off,
                             detail: i.briefingCardCount > 0 ? "\(i.briefingCardCount) card\(i.briefingCardCount == 1 ? "" : "s") today." : "No cards yet today.")
    }
}
