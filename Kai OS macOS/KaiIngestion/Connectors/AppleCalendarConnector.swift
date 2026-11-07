//
//  AppleCalendarConnector.swift
//  Kai OS macOS
//
//  Apple Calendar through KaiLocalData's EventKit source (read-only).
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import KaiLocalData

/// Reads the user's local Mac calendar. Throws `noCredentials` until the user grants access.
public final class AppleCalendarConnector: Connector {

    public static let shared = AppleCalendarConnector()

    public var name: String { "Apple Calendar" }
    public var status: ConnectorStatus = .idle

    public init() {}

    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        guard KaiCalendarSource.access == .granted else {
            throw ConnectorError.noCredentials(name: name)
        }
        let events = KaiCalendarSource.events(from: start, to: end)
        let first = min(max(page, 0) * max(pageSize, 1), events.count)
        let last = min(first + max(pageSize, 1), events.count)
        return events[first..<last].map { event in
            ConnectorItem(
                key: event.id,
                source: "apple-calendar",
                title: event.title,
                content: event.location.isEmpty ? "" : "At \(event.location)",
                timestamp: event.start
            )
        }
    }

    public func hasCredentials() async -> Bool {
        KaiCalendarSource.access == .granted
    }

    public func authenticate() async throws {
        guard try await KaiCalendarSource.requestAccess() else {
            throw ConnectorError.noCredentials(name: name)
        }
    }
}
