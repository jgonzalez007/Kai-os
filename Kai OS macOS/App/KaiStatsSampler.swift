//
//  KaiStatsSampler.swift
//  Kai OS macOS
//
//  Reads the Mac's CPU, memory, battery and heat for the notch's stats panel. It only reads while
//  something on screen is showing the numbers (a counted start and stop), every two seconds.
//

import Darwin
import Foundation
import IOKit.ps
import KaiShared

@MainActor
final class KaiStatsSampler: ObservableObject {
    static let shared = KaiStatsSampler()

    @Published private(set) var snapshot = KaiStatsSnapshot()
    @Published private(set) var now = Date()

    private var watchers = 0
    private var timer: Timer?
    private var lastTicks: KaiCPUTicks?

    /// Call when a view that shows stats appears. Pair every call with `stop()`.
    func start() {
        watchers += 1
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        lastTicks = nil
    }

    private func sample() {
        now = Date()
        var next = snapshot
        if let ticks = Self.readTicks() {
            if let last = lastTicks { next.cpuLoad = KaiCPUTicks.load(from: last, to: ticks) ?? next.cpuLoad }
            lastTicks = ticks
        }
        let memory = Self.readMemory()
        next.memoryUsedBytes = memory.used
        next.memoryTotalBytes = memory.total
        let battery = Self.readBattery()
        next.batteryPercent = battery.percent
        next.isCharging = battery.charging
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: next.thermal = .nominal
        case .fair: next.thermal = .fair
        case .serious: next.thermal = .serious
        case .critical: next.thermal = .critical
        @unknown default: next.thermal = .nominal
        }
        if next != snapshot { snapshot = next }
    }

    private static func readTicks() -> KaiCPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS, let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var total = KaiCPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let stride = Int(CPU_STATE_MAX)
        for core in 0..<Int(cpuCount) {
            total.user += UInt64(info[core * stride + Int(CPU_STATE_USER)])
            total.system += UInt64(info[core * stride + Int(CPU_STATE_SYSTEM)])
            total.idle += UInt64(info[core * stride + Int(CPU_STATE_IDLE)])
            total.nice += UInt64(info[core * stride + Int(CPU_STATE_NICE)])
        }
        return total
    }

    private static func readMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        // Memory in use the way Activity Monitor counts it: active, wired and compressed pages.
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    private static func readBattery() -> (percent: Int?, charging: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (Int((Double(current) / Double(max) * 100).rounded()), charging)
        }
        return (nil, false)
    }
}
