import Foundation

/// Read-only access to the user's Outlook calendar through Microsoft Graph.
public enum KaiOutlookCalendarSource {
    static let endpoint = "https://graph.microsoft.com/v1.0/me/calendarView"
    static let pageSize = 100
    static let maxPages = 5

    public enum SourceError: Error, Equatable {
        case http(Int)
        case badResponse
    }

    /// The first page of a calendar view. Times come back in UTC.
    public static func request(from start: Date, to end: Date, accessToken: String) -> URLRequest {
        let iso = ISO8601DateFormatter()
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "startDateTime", value: iso.string(from: start)),
            URLQueryItem(name: "endDateTime", value: iso.string(from: end)),
            URLQueryItem(name: "$top", value: String(pageSize)),
            URLQueryItem(name: "$orderby", value: "start/dateTime"),
            URLQueryItem(name: "$select", value: "id,subject,start,end,isAllDay,isCancelled,location")
        ]
        // URLComponents leaves "+" alone, but Graph reads it as a space.
        let query = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        components.percentEncodedQuery = query
        return authorized(URLRequest(url: components.url!), accessToken: accessToken)
    }

    static func authorized(_ request: URLRequest, accessToken: String) -> URLRequest {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        return request
    }

    public struct Page: Equatable {
        public let items: [KaiCalendarItem]
        public let nextLink: URL?
    }

    public static func parse(_ data: Data) throws -> Page {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = json["value"] as? [[String: Any]] else {
            throw SourceError.badResponse
        }
        let items = values.compactMap(item(from:))
        let next = (json["@odata.nextLink"] as? String).flatMap(URL.init(string:))
        return Page(items: items, nextLink: next)
    }

    private static func item(from event: [String: Any]) -> KaiCalendarItem? {
        if event["isCancelled"] as? Bool == true { return nil }
        guard let id = event["id"] as? String,
              let startText = (event["start"] as? [String: Any])?["dateTime"] as? String,
              let endText = (event["end"] as? [String: Any])?["dateTime"] as? String else { return nil }
        let allDay = event["isAllDay"] as? Bool ?? false
        guard let start = date(startText, allDay: allDay), let end = date(endText, allDay: allDay) else { return nil }
        let subject = (event["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        let location = (event["location"] as? [String: Any])?["displayName"] as? String ?? ""
        return KaiCalendarItem(
            id: "outlook-" + id,
            title: subject,
            start: start,
            end: end,
            isAllDay: allDay,
            location: location,
            calendarName: "Outlook"
        )
    }

    /// Graph sends "2026-11-07T10:00:00.0000000" with no zone, in UTC because of the Prefer header.
    /// An all-day event is a calendar date, so it is read as local midnight, not UTC midnight.
    static func date(_ text: String, allDay: Bool) -> Date? {
        let main = String(text.prefix(19))
        if allDay {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: String(main.prefix(10)))
        }
        return ISO8601DateFormatter().date(from: main + "Z")
    }

    /// Fetches every page, up to a limit, and returns events sorted by start.
    public static func events(
        from start: Date,
        to end: Date,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [KaiCalendarItem] {
        var items: [KaiCalendarItem] = []
        var next: URLRequest? = request(from: start, to: end, accessToken: accessToken)
        var pages = 0
        while let current = next, pages < maxPages {
            let (data, response) = try await session.data(for: current)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw SourceError.http(http.statusCode)
            }
            let page = try parse(data)
            items += page.items
            next = page.nextLink.map { authorized(URLRequest(url: $0), accessToken: accessToken) }
            pages += 1
        }
        return items.sorted { $0.start < $1.start }
    }

    /// Events for a window, using the signed-in account.
    public static func events(from start: Date, to end: Date) async throws -> [KaiCalendarItem] {
        let token = try await KaiMicrosoftAuth.validAccessToken()
        return try await events(from: start, to: end, accessToken: token)
    }
}
