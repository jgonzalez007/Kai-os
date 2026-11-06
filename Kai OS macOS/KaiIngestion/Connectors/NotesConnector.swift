//
//  NotesConnector.swift
//  Kai OS macOS
//
//  Apple Notes connector via AppleScript
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Apple Notes connector via AppleScript
public final class NotesConnector: Connector {
    
    public static let shared = NotesConnector()
    
    public init() {}
    
    public var name: String { "Apple Notes" }
    public var status: ConnectorStatus = .idle
    
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        return await withCheckedContinuation { continuation in
            let script = """
                tell application "Notes"
                    set noteContents to ""
                    tell folder "Notes"
                        repeat with note in every note
                            set noteContents to noteContents & (name of note) & " — " & (body of note) & "\\n"
                        end repeat
                    end tell
                    return noteContents
                end tell
                """
            
            let applescript = NSAppleScript(source: script)
            var errorDict: NSDictionary?
            let result = applescript?.executeAndReturnError(&errorDict)
            
            if let result = result, result.int32Value == 1 {
                if let text = result.stringValue {
                    let lines = text.components(separatedBy: "\\n")
                        .filter { !$0.isEmpty }
                        .prefix(pageSize)
                    let items = lines.map { line -> ConnectorItem in
                        let parts = line.components(separatedBy: " — ")
                        return ConnectorItem(
                            key: UUID().uuidString,
                            source: "apple-notes",
                            title: parts.first ?? "Note",
                            content: parts.dropFirst().joined(separator: " — "),
                            timestamp: nil
                        )
                    }
                    continuation.resume(returning: items)
                } else {
                    continuation.resume(returning: [])
                }
            } else {
                continuation.resume(returning: [])
            }
        }
    }
    
    public func hasCredentials() async -> Bool {
        return true
    }
    
    public func authenticate() async throws {
        throw ConnectorError.noCredentials(name: "Apple Notes")
    }
}
