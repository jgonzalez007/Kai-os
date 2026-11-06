//
//  AppleMailConnector.swift
//  Kai OS macOS
//
//  Apple Mail connector — fetches emails via AppleScript
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Apple Mail connector — fetches emails from Apple Mail.app
public final class AppleMailConnector: Connector {
    
    public static let shared = AppleMailConnector()
    
    public init() {}
    
    public var name: String { "Apple Mail" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch emails from Apple Mail
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        return await withCheckedContinuation { continuation in
            let script = """
            tell application "Mail"
                set foundMessages to {}
                repeat with msg in (get every message of inbox)
                    set msgDate to date received of msg
                    if msgDate ≥ (date "Tuesday, January 1, 2020 00:00:00") and msgDate ≤ (date "Monday, December 31, 2099 23:59:59") then
                        set end of foundMessages to {subject:subject of msg, from:(sender of msg), content:(content of msg)}
                    end if
                end repeat
                return foundMessages
            end tell
            """
            
            let applescript = NSAppleScript(source: script)
            var errorDict: NSDictionary?
            let result = applescript?.executeAndReturnError(&errorDict)
            
            if let result = result, result.int32Value == 1 {
                let items = result.stringValue?
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .prefix(pageSize)
                    .map { line -> ConnectorItem in
                        let parts = line.components(separatedBy: " — ")
                        return ConnectorItem(
                            key: "\(UUID().uuidString)",
                            source: "apple-mail",
                            title: parts.first ?? "Email",
                            content: parts.dropFirst().joined(separator: " — "),
                            timestamp: nil
                        )
                    }
                continuation.resume(returning: items ?? [])
            } else {
                continuation.resume(returning: [])
            }
        }
    }
    
    public func hasCredentials() async -> Bool {
        // Apple Mail uses system authentication
        return true
    }
    
    public func authenticate() async throws {
        // No authentication needed for Apple Mail (uses system credentials)
    }
}
