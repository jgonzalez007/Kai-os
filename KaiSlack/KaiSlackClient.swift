import Foundation
import KaiShared

/// Read-only access to Slack with a token the person created for their own Slack app.
/// It can read and search. It has no way to post, edit or delete anything.
public struct KaiSlackChannel: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case channel, privateChannel, groupDM, directMessage }
    public let id: String
    public let name: String
    public let kind: Kind
    /// For a direct message, the other person's user ID.
    public let userID: String?
}

public struct KaiSlackMessage: Equatable, Sendable {
    public let ts: String
    public let user: String?
    public let text: String
    public let threadTS: String?
    public let subtype: String?

    public var date: Date { Date(timeIntervalSince1970: Double(ts.split(separator: ".").first.flatMap { Double($0) } ?? 0)) }
}

public struct KaiSlackSearchHit: Equatable, Sendable {
    public let text: String
    public let username: String
    public let channelName: String
    public let ts: String
    public let permalink: String
}

public struct KaiSlackIdentity: Equatable, Sendable {
    public let team: String
    public let teamID: String
    public let user: String
    public let userID: String
    public let url: String
}

public enum KaiSlackError: Error, Equatable, LocalizedError, Sendable {
    case noToken
    case slack(String)
    case missingScope(String)
    case http(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .noToken: return "Slack isn't connected. Add your token in Settings."
        case .slack("invalid_auth"), .slack("token_revoked"), .slack("not_authed"), .slack("account_inactive"):
            return "Slack didn't accept the token. Paste a fresh User OAuth Token in Settings."
        case .slack(let code): return "Slack said: \(code)."
        case .missingScope(let scope): return "The Slack token is missing the \(scope) permission. Add it to your Slack app, reinstall the app, and paste the new token."
        case .http(let code): return "Slack returned HTTP \(code)."
        case .badResponse: return "Slack sent a reply Kai couldn't read."
        }
    }
}

public protocol KaiSlackTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct KaiURLSessionTransport: KaiSlackTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KaiSlackError.badResponse }
        return (data, http)
    }
}

public struct KaiSlackClient: Sendable {
    public static let base = "https://slack.com/api/"

    public let token: String
    public let transport: KaiSlackTransport
    public let pause: @Sendable (Duration) async -> Void

    public init(token: String, transport: KaiSlackTransport = KaiURLSessionTransport(),
                pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.token = token
        self.transport = transport
        self.pause = pause
    }

    // MARK: Requests

    public static func request(_ method: String, token: String, query: [String: String] = [:]) -> URLRequest {
        var components = URLComponents(string: base + method)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    /// One call, with one retry after a rate limit.
    func call(_ method: String, _ query: [String: String] = [:]) async throws -> [String: Any] {
        guard !token.isEmpty else { throw KaiSlackError.noToken }
        for attempt in 0...1 {
            let (data, http) = try await transport.send(Self.request(method, token: token, query: query))
            if http.statusCode == 429, attempt == 0 {
                let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 5
                await pause(.seconds(min(max(wait, 1), 30)))
                continue
            }
            guard (200...299).contains(http.statusCode) else { throw KaiSlackError.http(http.statusCode) }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw KaiSlackError.badResponse }
            if json["ok"] as? Bool != true {
                let code = json["error"] as? String ?? "unknown_error"
                if code == "missing_scope", let needed = json["needed"] as? String { throw KaiSlackError.missingScope(needed) }
                throw KaiSlackError.slack(code)
            }
            return json
        }
        throw KaiSlackError.http(429)
    }

    // MARK: Calls

    public func identity() async throws -> KaiSlackIdentity {
        let json = try await call("auth.test")
        guard let team = json["team"] as? String, let teamID = json["team_id"] as? String,
              let user = json["user"] as? String, let userID = json["user_id"] as? String else { throw KaiSlackError.badResponse }
        return KaiSlackIdentity(team: team, teamID: teamID, user: user, userID: userID, url: json["url"] as? String ?? "")
    }

    /// The channels the person is in. Direct messages are included only when asked for.
    public func channels(includeDirectMessages: Bool, limit: Int = 200) async throws -> [KaiSlackChannel] {
        var types = ["public_channel", "private_channel"]
        if includeDirectMessages { types += ["mpim", "im"] }
        var found: [KaiSlackChannel] = []
        var cursor = ""
        for _ in 0..<10 {
            var query = ["types": types.joined(separator: ","), "exclude_archived": "true", "limit": "200"]
            if !cursor.isEmpty { query["cursor"] = cursor }
            let json = try await call("users.conversations", query)
            found += Self.parseChannels(json)
            cursor = (json["response_metadata"] as? [String: Any])?["next_cursor"] as? String ?? ""
            if cursor.isEmpty || found.count >= limit { break }
        }
        return Array(found.prefix(limit))
    }

    public func history(channel: String, since: Date, limit: Int = 100) async throws -> [KaiSlackMessage] {
        let json = try await call("conversations.history", [
            "channel": channel, "oldest": String(format: "%.6f", since.timeIntervalSince1970), "limit": String(min(max(limit, 1), 200)),
        ])
        return Self.parseMessages(json).sorted { $0.ts < $1.ts }
    }

    public func displayName(userID: String) async throws -> String {
        let json = try await call("users.info", ["user": userID])
        guard let user = json["user"] as? [String: Any] else { throw KaiSlackError.badResponse }
        let profile = user["profile"] as? [String: Any]
        for candidate in [profile?["display_name"], user["real_name"], profile?["real_name"], user["name"]] {
            if let text = candidate as? String, !text.isEmpty { return text }
        }
        return userID
    }

    public func search(_ query: String, count: Int = 10) async throws -> [KaiSlackSearchHit] {
        let json = try await call("search.messages", ["query": query, "count": String(min(max(count, 1), 20)), "sort": "timestamp", "sort_dir": "desc"])
        return Self.parseSearch(json)
    }

    // MARK: Parsing

    static func parseChannels(_ json: [String: Any]) -> [KaiSlackChannel] {
        (json["channels"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let id = entry["id"] as? String else { return nil }
            let kind: KaiSlackChannel.Kind
            if entry["is_im"] as? Bool == true { kind = .directMessage }
            else if entry["is_mpim"] as? Bool == true { kind = .groupDM }
            else if entry["is_private"] as? Bool == true { kind = .privateChannel }
            else { kind = .channel }
            return KaiSlackChannel(id: id, name: entry["name"] as? String ?? "", kind: kind, userID: entry["user"] as? String)
        }
    }

    static func parseMessages(_ json: [String: Any]) -> [KaiSlackMessage] {
        (json["messages"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let ts = entry["ts"] as? String, let text = entry["text"] as? String else { return nil }
            return KaiSlackMessage(ts: ts, user: entry["user"] as? String, text: text, threadTS: entry["thread_ts"] as? String, subtype: entry["subtype"] as? String)
        }
    }

    static func parseSearch(_ json: [String: Any]) -> [KaiSlackSearchHit] {
        let matches = (json["messages"] as? [String: Any])?["matches"] as? [[String: Any]] ?? []
        return matches.compactMap { entry in
            guard let text = entry["text"] as? String, let ts = entry["ts"] as? String else { return nil }
            return KaiSlackSearchHit(text: text, username: entry["username"] as? String ?? "",
                                     channelName: (entry["channel"] as? [String: Any])?["name"] as? String ?? "",
                                     ts: ts, permalink: entry["permalink"] as? String ?? "")
        }
    }
}
