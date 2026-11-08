//
//  KaiStats.swift
//  Kai Shared
//
//  The numbers behind the notch's stats panel (clock, battery, CPU, memory, heat) and how they are
//  worded. Reading the Mac is done by the app. This file only does the arithmetic and the text, so
//  both can be tested.
//

import Foundation

public enum KaiStatsItem: String, CaseIterable, Codable, Sendable {
    case clock, battery, cpu, memory, thermal

    public static let defaultsKey = "kai.stats.items"
    public static let defaults: Set<KaiStatsItem> = Set(allCases)

    public var title: String {
        switch self {
        case .clock: return "Clock"
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .thermal: return "Heat"
        }
    }

    public var symbol: String {
        switch self {
        case .clock: return "clock"
        case .battery: return "battery.75percent"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        }
    }

    public static func stored(_ defaults: UserDefaults = .standard) -> Set<KaiStatsItem> {
        guard let raw = defaults.stringArray(forKey: defaultsKey) else { return Self.defaults }
        return Set(raw.compactMap(KaiStatsItem.init(rawValue:)))
    }

    public static func store(_ items: Set<KaiStatsItem>, _ defaults: UserDefaults = .standard) {
        defaults.set(allCases.filter(items.contains).map(\.rawValue), forKey: defaultsKey)
    }
}

/// CPU time counters, summed over every core, as macOS reports them.
public struct KaiCPUTicks: Equatable, Sendable {
    public var user: UInt64, system: UInt64, idle: UInt64, nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }

    /// Fraction of time busy between two readings, 0 to 1. Nil when nothing has advanced.
    public static func load(from older: KaiCPUTicks, to newer: KaiCPUTicks) -> Double? {
        guard newer.user >= older.user, newer.system >= older.system, newer.idle >= older.idle, newer.nice >= older.nice else { return nil }
        let busy = (newer.user - older.user) + (newer.system - older.system) + (newer.nice - older.nice)
        let total = busy + (newer.idle - older.idle)
        return total == 0 ? nil : Double(busy) / Double(total)
    }
}

public enum KaiThermal: String, Equatable, Sendable {
    case nominal, fair, serious, critical

    public var text: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        }
    }
}

public struct KaiStatsSnapshot: Equatable, Sendable {
    public var cpuLoad: Double?
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    /// Nil on a Mac with no battery.
    public var batteryPercent: Int?
    public var isCharging: Bool
    public var thermal: KaiThermal

    public init(cpuLoad: Double? = nil, memoryUsedBytes: UInt64 = 0, memoryTotalBytes: UInt64 = 0,
                batteryPercent: Int? = nil, isCharging: Bool = false, thermal: KaiThermal = .nominal) {
        self.cpuLoad = cpuLoad
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.batteryPercent = batteryPercent
        self.isCharging = isCharging
        self.thermal = thermal
    }

    public var cpuText: String {
        guard let cpuLoad else { return "…" }
        return "\(Int((min(max(cpuLoad, 0), 1) * 100).rounded()))%"
    }

    public var memoryFraction: Double? {
        memoryTotalBytes == 0 ? nil : min(1, Double(memoryUsedBytes) / Double(memoryTotalBytes))
    }

    public var memoryText: String {
        memoryFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…"
    }

    public var batteryText: String {
        guard let batteryPercent else { return "AC" }
        return "\(min(max(batteryPercent, 0), 100))%" + (isCharging ? " ⚡︎" : "")
    }

    /// A battery symbol that fits the charge.
    public var batterySymbol: String {
        guard let batteryPercent else { return "powerplug" }
        if isCharging { return "battery.100percent.bolt" }
        switch batteryPercent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// The headline value for one stat.
    public func value(for item: KaiStatsItem) -> String {
        switch item {
        case .clock: return ""
        case .battery: return batteryText
        case .cpu: return cpuText
        case .memory: return memoryText
        case .thermal: return thermal.text
        }
    }

    /// 0...1 for a gauge, or nil when the stat has no gauge.
    public func gauge(for item: KaiStatsItem) -> Double? {
        switch item {
        case .cpu: return cpuLoad
        case .memory: return memoryFraction
        case .battery: return batteryPercent.map { Double(min(max($0, 0), 100)) / 100 }
        case .thermal:
            switch thermal { case .nominal: return 0.15; case .fair: return 0.5; case .serious: return 0.8; case .critical: return 1 }
        case .clock: return nil
        }
    }
}
