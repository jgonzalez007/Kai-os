//
//  ChatConnectors.swift
//  Kai OS macOS
//
//  Chat platform connectors (stub)
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

/// Stub connector for WhatsApp
public final class WhatsAppConnector: Connector {
    public var name: String { "WhatsApp" }
    public var status: ConnectorStatus = .idle
    public func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem] {
        return []
    }
    public func hasCredentials() async -> Bool { return false }
    public func authenticate() async throws { throw ConnectorError.noCredentials(name: "WhatsApp") }
}

/// Stub connector for iMessage
public final class iMessageConnector: Connector {
    public var name: String { "iMessage" }
    public var status: ConnectorStatus = .idle
    public func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem] {
        return []
    }
    public func hasCredentials() async -> Bool { return false }
    public func authenticate() async throws { throw ConnectorError.noCredentials(name: "iMessage") }
}

/// Stub connector for Slack
public final class SlackConnector: Connector {
    public var name: String { "Slack" }
    public var status: ConnectorStatus = .idle
    public func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem] {
        return []
    }
    public func hasCredentials() async -> Bool { return false }
    public func authenticate() async throws { throw ConnectorError.noCredentials(name: "Slack") }
}
