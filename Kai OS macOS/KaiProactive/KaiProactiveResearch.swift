//
//  KaiProactiveResearch.swift
// import EventKit // STUB
//  Kai OS macOS
//
//  Research tool — mdfind and system calls for Spotlight search
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Proactive research results from local and remote sources
public struct ResearchResult {
    public let query: String
    public let source: ResearchSource
    public let title: String
    public let snippet: String
    public let location: String?
    public let timestamp: Date?
    
    public init(
        query: String,
        source: ResearchSource,
        title: String,
        snippet: String,
        location: String? = nil,
        timestamp: Date? = nil
    ) {
        self.query = query
        self.source = source
        self.title = title
        self.snippet = snippet
        self.location = location
        self.timestamp = timestamp
    }
}

/// Research source — where the result came from
public enum ResearchSource: String {
    case mdfind = "mdfind"
    case spotlight = "Spotlight"
    case systemInfo = "system_profiler"
    case calendar = "Calendar"
    case mail = "Mail"
    case webSearch = "Web Search"
    case localFiles = "Local Files"
    case knowledgeGraph = "Knowledge Graph"
}

/// ProactiveResearch — local search engine using mdfind, system_profiler, and file queries
public final class KaiProactiveResearch {
    
    public static let shared = KaiProactiveResearch()
    
    /// Cache for recent search results
    private var searchCache: [String: [ResearchResult]] = [:]
    private var lastSearchTimes: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    
    /// Maximum concurrent search operations
    private let maxConcurrentSearches = 4
    
    private init() {}
    
    // MARK: - Search
    
    /// Search using multiple local sources
    /// - Parameter query: The search query
    /// - Returns: Array of research results from local sources
    public func search(_ query: String) async throws -> [ResearchResult] {
        // Check cache first
        if let cached = searchCache[query],
           let lastTime = lastSearchTimes[query],
           Date().timeIntervalSince(lastTime) < cacheTTL {
            return cached
        }
        
        // Run all local searches in parallel
        let tasks: [(String, () async throws -> [ResearchResult])] = [
            ("mdfind", { try await self.searchMdfind(query) }),
            ("spotlight", { try await self.searchSpotlight(query) }),
            ("files", { try await self.searchLocalFiles(query) }),
            ("calendar", { try await self.searchCalendarEvents(query) }),
            ("mail", { try await self.searchMail(query) })
        ]
        
        var results: [ResearchResult] = []
        
        for (label, task) in tasks {
            do {
                let searchResults = try await task()
                results.append(contentsOf: searchResults)
            } catch {
                // Continue searching other sources even if one fails
                print("[KaiProactiveResearch] \(label) search failed: \(error.localizedDescription)")
            }
        }
        
        // Cache the results
        searchCache[query] = results
        lastSearchTimes[query] = Date()
        
        return results
    }
    
    // MARK: - mdfind Search
    
    /// Search using mdfind — macOS metadata search (Spotlight backend)
    private func searchMdfind(_ query: String) async throws -> [ResearchResult] {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/mdfind"
            process.arguments = ["-onlyin", "\(NSHomeDirectory())", query]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                let data = try outputPipe.fileHandleForReading.readToEnd()
                guard let output = String(data: data ?? Data(), encoding: .utf8),
                      !output.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }
                
                let lines = output.components(separatedBy: "\n")
                    .filter { !$0.isEmpty && $0.hasSuffix(".md") == false || $0.hasSuffix(".txt") }
                    .prefix(20) // Limit to top 20 results
                
                continuation.resume(returning: lines.map { line in
                    
                        ResearchResult(
                        query: query,
                        source: .mdfind,
                        title: URL(fileURLWithPath: line).lastPathComponent,
                        snippet: line,
                        location: line
                    )
                })
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - Spotlight Search
    
    /// Search using Spotlight metadata attributes
    private func searchSpotlight(_ query: String) async throws -> [ResearchResult] {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/mdfind"
            process.arguments = [
                "-name", query,
                "-k", "kMDItemContentType",
                "com.apple.mail-email",
                "public.plain-text",
                "public.markdown",
                "public.calendar-event"
            ]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                let data = try outputPipe.fileHandleForReading.readToEnd()
                let output = String(data: data ?? Data(), encoding: .utf8) ?? ""
                
                let lines = output.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .prefix(10)
                
                continuation.resume(returning: lines.map { line in
                    
                        return ResearchResult(
                        query: query,
                        source: .spotlight,
                        title: URL(fileURLWithPath: line).lastPathComponent,
                        snippet: "Found via Spotlight metadata",
                        location: line
                    )
                })
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - Local Files
    
    /// Search local files in the knowledge base
    private func searchLocalFiles(_ query: String) async throws -> [ResearchResult] {
        let home = NSHomeDirectory()
        let knowledgePaths = [
            "\(home)/Kai OS - Knowledge Base",
            "\(home)/Documents/Kai",
            "\(home)/Library/Application Support/Kai"
        ]
        
        var results: [ResearchResult] = []
        
        for path in knowledgePaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            
            let predicate = NSPredicate(format: "self CONTAINS[c] %@", query)
            let fileManager = FileManager.default
            let files = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.nameKey]
            ).filter { file in
                file.pathExtension == "md" || file.pathExtension == "txt"
            }
            
            if let files = files {
                results.append(contentsOf: files.prefix(10).map { file in
                    
                        return ResearchResult(
                        query: query,
                        source: .localFiles,
                        title: file.lastPathComponent,
                        snippet: "Local file in \(path)",
                        location: file.path
                    )
                })
            }
        }
        
        return results
    }
    
    // MARK: - Calendar Search
    
    /// Search calendar events matching the query
    private func searchCalendarEvents(_ query: String) async throws -> [ResearchResult] {
        return await withCheckedContinuation { continuation in
            let store = EKEventStore()
            store.requestAccess(for: .event) { authorized, error in
                guard authorized else {
                    continuation.resume(returning: [])
                    return
                }
                
                let predicate = store.predicateForEvents(
                    withStart: Calendar.current.date(
                        byAdding: .day, value: -30, to: Date()
                    ) ?? Date(),
                    end: Date(),
                    calendars: nil
                )
                
                let events = store.events(matching: predicate)
                    .filter { event in
                        event.title.localizedCaseInsensitiveContains(query) ||
                        (event.notes ?? "").localizedCaseInsensitiveContains(query)
                    }
                    .prefix(15)
                
                continuation.resume(returning: events.map { event in
                    
                        return ResearchResult(
                        query: query,
                        source: .calendar,
                        title: event.title,
                        snippet: event.notes ?? "",
                        timestamp: event.startDate
                    )
                })
            }
        }
    }
    
    // MARK: - Mail Search
    
    /// Search Apple Mail for matching messages
    private func searchMail(_ query: String) async throws -> [ResearchResult] {
        // Use AppleScript to search Mail.app
        return await withCheckedContinuation { continuation in
            let script = """
            tell application "Mail"
                set foundMessages to {}
                set allMessages to every message of every mailbox of every account
                repeat with msg in allMessages
                    set msgSubject to subject of msg as text
                    set msgContent to content of msg as text
                    if (msgSubject contains "\(query)" or msgContent contains "\(query)") then
                        set end of foundMessages to msgSubject & " — " & (msgContent as text)
                    end if
                end repeat
                return foundMessages
            end tell
            """
            
            do {
                let applescript = NSAppleScript(source: script)
                var errorDict: NSDictionary?
                let result = applescript?.executeAndReturnError(&errorDict)
                
                if let result = result, result.int32Value == 1 {
                    let items = result.stringValue?
                        .components(separatedBy: "\n")
                        .filter { !$0.isEmpty }
                        .prefix(15) ?? []
                    
                    continuation.resume(returning: items.map { item in
                        let parts = item.components(separatedBy: " — ")
                        
                        return ResearchResult(
                            query: query,
                            source: .mail,
                            title: parts.first ?? "Message",
                            snippet: parts.dropFirst().joined(separator: " — ")
                        )
                    })
                } else {
                    continuation.resume(returning: [])
                }
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - System Profiler
    
    /// Run system_profiler to gather system information
    public func gatherSystemInfo(_ query: String) async throws -> [ResearchResult] {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/sbin/system_profiler"
            process.arguments = [
                "SPDataType",
                "-json"
            ]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                let data = try outputPipe.fileHandleForReading.readToEnd()
                let output = String(data: data ?? Data(), encoding: .utf8) ?? ""
                
                let results: [ResearchResult] = [
                    
                        ResearchResult(
                        query: query,
                        source: .systemInfo,
                        title: "System Profiler",
                        snippet: String(output.prefix(500))
                    )
                ]
                
                continuation.resume(returning: results)
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear the search cache
    public func clearCache() {
        searchCache.removeAll()
        lastSearchTimes.removeAll()
    }
    
    /// Force refresh a specific query (bypass cache)
    public func refresh(_ query: String) async throws -> [ResearchResult] {
        searchCache.removeValue(forKey: query)
        return try await search(query)
    }
}
