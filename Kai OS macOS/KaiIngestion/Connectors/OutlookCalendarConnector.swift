//
//  OutlookCalendarConnector.swift
//  Kai OS macOS
//
//  Outlook Calendar connector via Microsoft Graph API
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Outlook Calendar connector — fetches events from Microsoft Graph API
/// Uses OAuth2 access tokens stored in SecureStore
public final class OutlookCalendarConnector: Connector {
    
    public static let shared = OutlookCalendarConnector()
    
    private let baseURL = "https://graph.microsoft.com/v1.0"
    
    public init() {}
    
    public var name: String { "Outlook Calendar" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch calendar events for a date range
    /// - Parameters:
    ///   - start: Start of the query window
    ///   - end: End of the query window
    /// - Returns: Array of calendar event summaries
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        guard let accessToken = try await SecureStore.shared.read(key: "kai.microsoft.calendar.access_token") else {
            throw ConnectorError.noCredentials(name: "Outlook Calendar")
        }
        
        let formatter = ISO8601DateFormatter()
        let startTime = formatter.string(from: start)
        let endTime = formatter.string(from: end)
        
        let url = URL(string: "\(baseURL)/me/calendarview?startdatetime=\(startTime)&enddatetime=\(endTime)&top=\(pageSize)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("Outlook Calendar", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConnectorError.apiError("Outlook Calendar", httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["value"] as? [[String: Any]] ?? []
        
        return items.compactMap { item -> ConnectorItem? in
            guard let subject = item["subject"] as? String,
                  let startDict = item["start"] as? [String: Any],
                  let startTimeString = startDict["dateTime"] as? String else {
                return nil
            }
            return ConnectorItem(
                key: item["id"] as? String ?? UUID().uuidString,
                source: "outlook-calendar",
                title: subject,
                content: buildEventDescription(from: item),
                timestamp: ISO8601DateFormatter().date(from: startTimeString)
            )
        }
    }
    
    /// Build a human-readable event description from the Graph API item
    private func buildEventDescription(from item: [String: Any]) -> String {
        var parts: [String] = []
        
        if let bodyDict = item["body"] as? [String: Any], let body = bodyDict["content"] as? String, !body.isEmpty {
            parts.append(body)
        }
        if let dict = item["attendees"] as? [[String: Any]] {
            parts.append("👥 \(dict.count) attendees")
        }
        if let locDict = item["location"] as? [String: Any],
           let location = locDict["displayName"] as? String, !location.isEmpty {
            parts.append("📍 \(location)")
        }
        
        return parts.joined(separator: "\n")
    }
    
    public func hasCredentials() async -> Bool {
        return try await SecureStore.shared.read(key: "kai.microsoft.calendar.access_token") != nil
    }
    
    public func authenticate() async throws {
        throw ConnectorError.noCredentials(name: "Outlook Calendar")
    }
}
