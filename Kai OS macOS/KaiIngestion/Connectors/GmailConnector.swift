//
//  GmailConnector.swift
//  Kai OS macOS
//
//  Gmail connector — fetches emails via Gmail API
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Gmail connector — fetches emails from Gmail via Google API
public final class GmailConnector: Connector {
    
    public static let shared = GmailConnector()
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users"
    
    public init() {}
    
    public var name: String { "Gmail" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch emails from Gmail
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        guard let accessToken = try await SecureStore.shared.read(key: "kai.gmail.access_token") else {
            throw ConnectorError.noCredentials(name: "Gmail")
        }
        
        let userId = "me"
        let url = URL(string: "\(baseURL)/\(userId)/messages?maxResults=\(pageSize)&pageToken=\(page)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ConnectorError.apiError("Gmail", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]] ?? []
        
        return try await withThrowingTaskGroup(of: ConnectorItem.self) { group in
            var items: [ConnectorItem] = []
            
            for message in messages {
                group.addTask {
                    let id = message["id"] as? String ?? UUID().uuidString
                    let rawUrl = URL(string: "\(self.baseURL)/\(userId)/messages/\(id)?format=raw")!
                    
                    var req = URLRequest(url: rawUrl)
                    req.httpMethod = "GET"
                    req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    
                    let (rawData, _) = try await URLSession.shared.data(for: req)
                    let rawString = String(data: rawData, encoding: .utf8) ?? ""
                    
                    // Parse the raw MIME for subject and body
                    let lines = rawString.components(separatedBy: "\n")
                    var subject = "Email"
                    var body = ""
                    
                    var inBody = false
                    for line in lines {
                        if line.hasPrefix("Subject:") {
                            subject = line.replacingOccurrences(of: "Subject: ", with: "")
                        } else if line.isEmpty {
                            inBody = true
                        } else if inBody {
                            body += line + "\n"
                        }
                    }
                    
                    return ConnectorItem(
                        key: id,
                        source: "gmail",
                        title: subject,
                        content: body,
                        timestamp: nil
                    )
                }
            }
            
            for try await item in group {
                items.append(item)
            }
            
            return items
        }
    }
    
    public func hasCredentials() async -> Bool {
        return try await SecureStore.shared.read(key: "kai.gmail.access_token") != nil
    }
    
    public func authenticate() async throws {
        throw ConnectorError.noCredentials(name: "Gmail")
    }
}
