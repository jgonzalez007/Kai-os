//
//  AppleCalendarConnector.swift
//  Kai OS macOS
//
//  Apple Calendar
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI
// import EventKit // STUB

/// Apple Calendar connector via EventKit
public final class AppleCalendarConnector: Connector {
    public static let shared = AppleCalendarConnector()
    public init() {}
    public var name: String { "Apple Calendar" }
    public var status: ConnectorStatus = .idle
    
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        return []
    }
    
    public func hasCredentials() async -> Bool {
        return true
    }
    
    public func authenticate() async throws {
        // EventKit does not require explicit auth
    }
}
