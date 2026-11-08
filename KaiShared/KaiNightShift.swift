import Foundation
import IOKit.ps

// Night Shift: a scheduled, unattended run that indexes the knowledge base and prepares the
// morning briefing. It only prepares cards. It never runs an action.

/// Something Night Shift can read or prepare. The person chooses which, and the same choice decides what
/// "Index now" and the morning briefing read.
public enum KaiNightShiftSource: String, Codable, CaseIterable, Hashable, Sendable {
    case files, calendar, notes, mail, slack, briefing

    public var title: String {
        switch self {
        case .files: return "Knowledge folder"
        case .calendar: return "Calendar"
        case .notes: return "Notes"
        case .mail: return "Mail"
        case .slack: return "Slack"
        case .briefing: return "Morning cards"
        }
    }

    public var detail: String {
        switch self {
        case .files: return "Markdown and text files in your knowledge folder."
        case .calendar: return "Events from 30 days back to 90 days ahead."
        case .notes: return "Your recent Apple Notes."
        case .mail: return "Sender and subject of recent messages, read one at a time. Apple Mail can be very slow on a big mailbox, so leave this off if yours has thousands of messages."
        case .slack: return "Recent messages from your channels (and direct messages, if you allowed them)."
        case .briefing: return "Prepare today's morning cards from what is selected above."
        }
    }

    /// Mail is off until chosen: reading it is slow and can tie up Apple Mail.
    public static let defaults: Set<KaiNightShiftSource> = [.files, .calendar, .notes, .slack, .briefing]
}

public struct KaiNightShiftSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int
    public var sources: Set<KaiNightShiftSource>

    public init(enabled: Bool = false, hour: Int = 3, minute: Int = 0, sources: Set<KaiNightShiftSource> = KaiNightShiftSource.defaults) {
        self.enabled = enabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey { case enabled, hour, minute, sources }

    /// Settings saved before the checklist existed have no `sources`, and get the defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try? container.decodeIfPresent(Set<KaiNightShiftSource>.self, forKey: .sources)
        self.init(enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
                  hour: try container.decodeIfPresent(Int.self, forKey: .hour) ?? 3,
                  minute: try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
                  sources: saved ?? KaiNightShiftSource.defaults)
    }

    public func includes(_ source: KaiNightShiftSource) -> Bool { sources.contains(source) }

    /// The next time the job fires after `now`, in the Mac's local time.
    public func nextRun(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
    }
}

public struct KaiNightShiftRecord: Codable, Equatable, Sendable {
    public enum Outcome: Codable, Equatable, Sendable {
        case completed
        case skipped(String)
        case failed(String)
    }

    public var ranAt: Date
    public var outcome: Outcome
    public var documentsIndexed: Int
    public var cardsPrepared: Int

    public init(ranAt: Date, outcome: Outcome, documentsIndexed: Int = 0, cardsPrepared: Int = 0) {
        self.ranAt = ranAt
        self.outcome = outcome
        self.documentsIndexed = documentsIndexed
        self.cardsPrepared = cardsPrepared
    }

    public var summary: String {
        switch outcome {
        case .completed: return "Indexed \(documentsIndexed) document\(documentsIndexed == 1 ? "" : "s"), prepared \(cardsPrepared) card\(cardsPrepared == 1 ? "" : "s")."
        case .skipped(let reason): return "Skipped: \(reason)"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

public struct KaiPowerState: Equatable, Sendable {
    public var isOnBattery: Bool
    public var batteryPercent: Int?
    public var lowPowerMode: Bool
    public var thermal: ProcessInfo.ThermalState

    public init(isOnBattery: Bool = false, batteryPercent: Int? = nil, lowPowerMode: Bool = false, thermal: ProcessInfo.ThermalState = .nominal) {
        self.isOnBattery = isOnBattery
        self.batteryPercent = batteryPercent
        self.lowPowerMode = lowPowerMode
        self.thermal = thermal
    }

    public static func current() -> KaiPowerState {
        var onBattery = false
        var percent: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
                if (description[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue { onBattery = true }
                if let now = description[kIOPSCurrentCapacityKey] as? Int, let full = description[kIOPSMaxCapacityKey] as? Int, full > 0 {
                    percent = now * 100 / full
                }
            }
        }
        return KaiPowerState(isOnBattery: onBattery, batteryPercent: percent,
                             lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                             thermal: ProcessInfo.processInfo.thermalState)
    }
}

public enum KaiNightShiftPolicy {
    public static let minimumBatteryPercent = 30

    /// A reason not to run unattended right now, or nil when it is fine to go ahead.
    public static func skipReason(_ power: KaiPowerState) -> String? {
        if power.lowPowerMode { return "Low Power Mode is on." }
        if power.thermal == .serious || power.thermal == .critical { return "The Mac is running hot." }
        if power.isOnBattery, let percent = power.batteryPercent, percent < minimumBatteryPercent {
            return "The battery is at \(percent)% and not charging."
        }
        return nil
    }
}

/// Settings and the last run, kept in ~/Library/Application Support/Kai OS.
public struct KaiNightShiftStore: Sendable {
    public let directory: URL

    public init(directory: URL = KaiNightShiftStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kai OS", isDirectory: true)
    }

    private var settingsURL: URL { directory.appendingPathComponent("night-shift-settings.json") }
    private var recordURL: URL { directory.appendingPathComponent("night-shift-last-run.json") }

    public func loadSettings() -> KaiNightShiftSettings {
        load(KaiNightShiftSettings.self, from: settingsURL) ?? KaiNightShiftSettings()
    }

    public func save(_ settings: KaiNightShiftSettings) throws { try write(settings, to: settingsURL) }

    public func loadRecord() -> KaiNightShiftRecord? { load(KaiNightShiftRecord.self, from: recordURL) }

    public func save(_ record: KaiNightShiftRecord) throws { try write(record, to: recordURL) }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Installs and removes the per-user launchd job that starts Kai OS in the background.
/// It lives in ~/Library/LaunchAgents and affects only this user.
public struct KaiNightShiftAgent: Sendable {
    public static let label = "ai.kai.nightshift"
    public static let launchArgument = "--night-shift"

    public typealias Launchctl = @Sendable ([String]) -> Bool

    public let agentsDirectory: URL
    public let logDirectory: URL
    public let userID: UInt32
    public let launchctl: Launchctl

    public init(
        agentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        logDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Kai OS", isDirectory: true),
        userID: UInt32 = getuid(),
        launchctl: @escaping Launchctl = KaiNightShiftAgent.systemLaunchctl
    ) {
        self.agentsDirectory = agentsDirectory
        self.logDirectory = logDirectory
        self.userID = userID
        self.launchctl = launchctl
    }

    public var plistURL: URL { agentsDirectory.appendingPathComponent("\(Self.label).plist") }
    public var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    public func plist(executable: String, hour: Int, minute: Int) throws -> Data {
        let job: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable, Self.launchArgument],
            "StartCalendarInterval": ["Hour": hour, "Minute": minute],
            "RunAtLoad": false,
            "ProcessType": "Background",
            "LowPriorityIO": true,
            "StandardOutPath": logDirectory.appendingPathComponent("night-shift.log").path,
            "StandardErrorPath": logDirectory.appendingPathComponent("night-shift.log").path,
        ]
        return try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    }

    /// Writes the job file and loads it. Replaces an earlier copy, so a new time takes effect.
    @discardableResult
    public func install(executable: String, hour: Int, minute: Int) throws -> Bool {
        try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        _ = launchctl(["bootout", "gui/\(userID)/\(Self.label)"])
        try plist(executable: executable, hour: hour, minute: minute).write(to: plistURL, options: .atomic)
        return launchctl(["bootstrap", "gui/\(userID)", plistURL.path])
    }

    public func uninstall() throws {
        _ = launchctl(["bootout", "gui/\(userID)/\(Self.label)"])
        if isInstalled { try FileManager.default.removeItem(at: plistURL) }
    }

    public static let systemLaunchctl: Launchctl = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
