//
//  GoogleCalendarConnector.swift
//  Kai OS macOS
//
//  Google Calendar connector via Google Calendar API
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI

/// Google Calendar connector — fetches events from Google Calendar API
/// Uses OAuth2 access tokens stored in SecureStore
public final class GoogleCalendarConnector: Connector {
    
    public static let shared = GoogleCalendarConnector()
    
    private let baseURL = "https://www.googleapis.com/calendar/v3"
    private let calendarAPIVersion = "v3"
    
    public init() {}
    
    public var name: String { "Google Calendar" }
    public var status: ConnectorStatus = .idle
    
    /// Fetch calendar events for a date range
    /// - Parameters:
    ///   - start: Start of the query window
    ///   - end: End of the query window
    /// - Returns: Array of calendar event summaries
    public func fetch(start: Date, end: Date, page: Int = 0, pageSize: Int = 50) async throws -> [ConnectorItem] {
        guard let accessToken = try await SecureStore.shared.read(key: "kai.google.calendar.access_token") else {
            throw ConnectorError.noCredentials(name: "Google Calendar")
        }
        
        let formatter = ISO8601DateFormatter()
        let startTime = formatter.string(from: start)
        let endTime = formatter.string(from: end)
        
        var components = URLComponents(string: "\(baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: startTime),
            URLQueryItem(name: "timeMax", value: endTime),
            URLQueryItem(name: "maxResults", value: "\(pageSize)"),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        guard let url = components.url else {
            throw ConnectorError.invalidURL("Google Calendar events list")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectorError.apiError("Google Calendar", (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ConnectorError.apiError("Google Calendar", httpResponse.statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = json?["items"] as? [[String: Any]] ?? []
        
        return items.compactMap { item -> ConnectorItem? in
            guard let summary = item["summary"] as? String,
                  let startDict = item["start"] as? [String: Any],
                  let startTimeString = startDict["dateTime"] as? String ?? startDict["date"] as? String else {
                return nil
            }
            return ConnectorItem(
                key: item["id"] as? String ?? UUID().uuidString,
                source: "google-calendar",
                title: summary,
                content: buildEventDescription(from: item),
                timestamp: ISO8601DateFormatter().date(from: startTimeString)
            )
        }
    }
    
    /// Build a human-readable event description from the API item
    private func buildEventDescription(from item: [String: Any]) -> String {
        var parts: [String] = []
        
        if let location = item["location"] as? String, !location.isEmpty {
            parts.append("📍 \(location)")
        }
        if let attendees = item["attendees"] as? [[String: Any]] {
            parts.append("👥 \(attendees.count) attendees")
        }
        if let description = item["description"] as? String, !description.isEmpty {
            parts.append(description)
        }
        
        return parts.joined(separator: "\n")
    }
    
    public func hasCredentials() async -> Bool {
        return try await SecureStore.shared.read(key: "kai.google.calendar.access_token") != nil
    }
    
    public func authenticate() async throws {
        throw ConnectorError.noCredentials(name: "Google Calendar")
    }
}
