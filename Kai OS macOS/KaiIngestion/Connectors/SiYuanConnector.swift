//
//  SiYuanConnector.swift
//  Kai OS macOS
//
//  SiYuan Note connector (stub)
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

/// SiYuan Note connector stub
public final class SiYuanConnector: Connector {
    public var name: String { "SiYuan" }
    public var status: ConnectorStatus = .idle
    public func fetch(start: Date, end: Date, page: Int, pageSize: Int) async throws -> [ConnectorItem] {
        return []
    }
    public func hasCredentials() async -> Bool { return false }
    public func authenticate() async throws { throw ConnectorError.noCredentials(name: "SiYuan") }
}
