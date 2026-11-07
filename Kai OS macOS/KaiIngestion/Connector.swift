//
//  Connector.swift
//  Kai OS macOS
//
//  Connector protocol — base interface for all data connectors
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Connector status — indicates the current state of a data connector
public enum ConnectorStatus: String {
    case idle = "Idle"
    case connecting = "Connecting"
    case active = "Active"
    case syncing = "Syncing"
    case error = "Error"
    case unauthorized = "Unauthorized"
    
    /// Whether the connector is currently usable
    public var isActive: Bool {
        switch self {
        case .active, .syncing:
            return true
        case .idle, .connecting, .error, .unauthorized:
            return false
        }
    }
}

/// A data item from a connector
public struct ConnectorItem {
    public let key: String
    public let source: String
    public let title: String
    public let content: String
    public let timestamp: Date?
    
    public init(
        key: String,
        source: String,
        title: String,
        content: String,
        timestamp: Date? = nil
    ) {
        self.key = key
        self.source = source
        self.title = title
        self.content = content
        self.timestamp = timestamp
    }
}

/// Connector errors
public enum ConnectorError: Error, LocalizedError {
    case noCredentials(name: String)
    case invalidURL(String)
    case apiError(String, Int)
    case networkFailure(String)
    case invalidResponse(String)
    case rateLimited
    
    public var errorDescription: String? {
        switch self {
        case .noCredentials(let name):
            return "\(name) requires authentication"
        case .invalidURL(let name):
            return "Invalid URL for \(name)"
        case .apiError(let name, let code):
            return "\(name) API error: \(code)"
        case .networkFailure(let reason):
            return "Network failure: \(reason)"
        case .invalidResponse(let name):
            return "Invalid response from \(name)"
        case .rateLimited:
            return "Rate limited — slow down"
        }
    }
}

/// Base protocol for all data connectors
public protocol Connector: AnyObject {
    var name: String { get }
    var status: ConnectorStatus { get set }
    
    /// Fetch data items from the connector
    /// - Parameters:
    ///   - start: Start of the query window
    ///   - end: End of the query window
    ///   - page: Page number for pagination
    ///   - pageSize: Number of items per page
    /// - Returns: Array of data items
    func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem]
    
    /// Check if the connector has valid credentials
    func hasCredentials() async -> Bool
    
    /// Authenticate the connector (triggers OAuth flow if needed)
    func authenticate() async throws
}

/// Connector factory — creates connector instances by name
public final class ConnectorFactory {
    
    /// All registered connector names
    public static var registeredConnectors: [String] {
        return [
            "Apple Mail",
            "Gmail",
            "Apple Calendar",
            "Google Calendar",
            "Outlook Calendar",
            "Apple Notes",
            "SiYuan",
            "WhatsApp",
            "iMessage",
            "Slack",
            "Notion",
            "SiYuan",
            "Files",
            "Direct MCP"
        ]
    }
    
    /// Create a connector by name
    public static func create(name: String) -> Connector? {
        switch name {
        case "Apple Mail":
            return AppleMailConnector()
        case "Gmail":
            return GmailConnector()
        case "Apple Calendar":
            return AppleCalendarConnector()
        case "Google Calendar":
            return GoogleCalendarConnector()
        case "Apple Notes":
            return NotesConnector()
        case "Files":
            return FilesConnector()
        default:
            // Return a stub connector for unimplemented types
            return StubConnector(name: name)
        }
    }
    
    /// Get all available connectors
    public static func allConnectors() -> [Connector] {
        return registeredConnectors.compactMap { create(name: $0) }
    }
}

/// Stub connector for unimplemented types
public final class StubConnector: Connector {
    public let name: String
    public var status: ConnectorStatus = .idle
    
    public init(name: String) {
        self.name = name
    }
    
    public func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem] {
        throw ConnectorError.noCredentials(name: name)
    }
    
    public func hasCredentials() async -> Bool {
        return false
    }
    
    public func authenticate() async throws {
        throw ConnectorError.noCredentials(name: name)
    }
}
