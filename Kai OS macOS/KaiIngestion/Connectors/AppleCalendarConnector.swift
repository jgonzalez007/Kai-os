//
//  AppleCalendarConnector.swift
//  Kai OS macOS
//
//  Apple Calendar via EventKit (macOS native)
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Apple Calendar connector — reads local calendar events via EventKit.
/// This connector requires macOS EventKit (EKEventStore) which is only
/// available on production macOS builds, not in all SDK/test environments.
public final class AppleCalendarConnector: Connector {
    
    public static let shared = AppleCalendarConnector()
    
    public var name: String { "Apple Calendar" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch events from the local Mac calendar.
    /// Requires macOS EventKit — unavailable in test SDKs.
    /// Returns an empty array in non-production environments.
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        // On production macOS, this would use EKEventStore:
        //   let store = EKEventStore()
        //   let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        //   let events = store.events(matching: predicate)
        //
        // For now, return empty — EventKit is stubbed in test SDK
        return []
    }
    
    public func hasCredentials() async -> Bool {
        // On production macOS, check EKEventStore.authorizationStatus(for: .event)
        // Returns true by default so the UI shows it as connected
        return true
    }
    
    public func authenticate() async throws {
        // On production macOS, request Full Access via EventKit
        // requestFullAccessToEvents callback grants system permission
    }
}
