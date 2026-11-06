//
//  FilesConnector.swift
//  Kai OS macOS
//
//  Local file system connector — watches and reads local files
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Files connector — reads local markdown/text files from the knowledge base
public final class FilesConnector: Connector {
    
    public static let shared = FilesConnector()
    
    public init() {}
    
    public var name: String { "Files" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch content from local files matching the date range
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        let home = NSHomeDirectory()
        let searchPaths = [
            "\(home)/Kai OS - Knowledge Base",
            "\(home)/Documents/Kai",
            "\(home)/Library/Application Support/Kai"
        ]
        
        let fileManager = FileManager.default
        var items: [ConnectorItem] = []
        
        for basePath in searchPaths {
            guard fileManager.fileExists(atPath: basePath) else { continue }
            
            let urls = try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.contentModificationDateKey, .nameKey]
            )
            
            guard let urls = urls else { continue }
            
            let matchingFiles = urls.filter { url in
                ["md", "txt"].contains(url.pathExtension)
            }.prefix(pageSize)
            
            for url in matchingFiles {
                let content = try? String(contentsOf: url, encoding: .utf8)
                let timestamp = try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
                
                items.append(ConnectorItem(
                    key: url.path,
                    source: "local-files",
                    title: url.lastPathComponent,
                    content: content ?? "",
                    timestamp: timestamp
                ))
            }
        }
        
        return items
    }
    
    public func hasCredentials() async -> Bool {
        return true // No auth needed for local files
    }
    
    public func authenticate() async throws {
        // No authentication needed for local files
    }
}
