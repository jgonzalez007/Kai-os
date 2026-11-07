import Foundation
import CryptoKit
import KaiShared

/// Microsoft identity platform sign-in for a public (desktop) client, using the
/// authorization code flow with PKCE. The app registration (client ID) belongs to
/// the user: register a "Mobile and desktop application" in Microsoft Entra with the
/// redirect URI `KaiMicrosoftAuth.redirectURI` and the delegated permission
/// `Calendars.Read`.
///
/// This type builds requests and parses responses. It never opens a browser: the
/// interactive step lives in the app target.
public enum KaiMicrosoftAuth {
    public static let redirectURI = "kai-os://auth/microsoft"
    public static let callbackScheme = "kai-os"
    public static let scopes = "Calendars.Read offline_access"
    static let authority = "https://login.microsoftonline.com/common/oauth2/v2.0"

    static let clientIDDefaultsKey = "kai.microsoft.clientID"
    static let expiryDefaultsKey = "kai.microsoft.accessExpiry"
    static let accessKeychainName = "microsoft.access"
    static let refreshKeychainName = "microsoft.refresh"

    public enum AuthError: Error, Equatable {
        case noClientID
        case notSignedIn
        case server(String)
        case badResponse
    }

    public struct Tokens: Equatable, Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date
    }

    // MARK: PKCE

    public static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URL(Data(bytes))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Requests

    public static func authorizeURL(clientID: String, challenge: String, state: String) -> URL? {
        var components = URLComponents(string: authority + "/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_mode", value: "query"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    /// Reads `code` out of the redirect, checking `state` and surfacing a returned error.
    public static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw AuthError.server(value("error_description") ?? error)
        }
        guard value("state") == expectedState, let code = value("code"), !code.isEmpty else {
            throw AuthError.badResponse
        }
        return code
    }

    public static func codeExchangeRequest(clientID: String, code: String, verifier: String) -> URLRequest {
        formRequest([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
            "scope": scopes
        ])
    }

    public static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        formRequest([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": scopes
        ])
    }

    private static func formRequest(_ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: authority + "/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.sorted { $0.key < $1.key }.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").data(using: .utf8)
        return request
    }

    // MARK: Responses

    public static func parseTokens(_ data: Data, now: Date = Date()) throws -> Tokens {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.badResponse
        }
        if let error = json["error"] as? String {
            throw AuthError.server(json["error_description"] as? String ?? error)
        }
        guard let access = json["access_token"] as? String, !access.isEmpty else { throw AuthError.badResponse }
        let seconds = (json["expires_in"] as? Double) ?? 3600
        return Tokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: now.addingTimeInterval(seconds)
        )
    }

    // MARK: Stored state

    public static var clientID: String {
        get { UserDefaults.standard.string(forKey: clientIDDefaultsKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDDefaultsKey) }
    }

    public static var isSignedIn: Bool {
        KaiKeychain.apiKey(for: refreshKeychainName) != nil
    }

    public static func store(_ tokens: Tokens) {
        KaiKeychain.setApiKey(tokens.accessToken, for: accessKeychainName)
        if let refresh = tokens.refreshToken {
            KaiKeychain.setApiKey(refresh, for: refreshKeychainName)
        }
        UserDefaults.standard.set(tokens.expiresAt.timeIntervalSince1970, forKey: expiryDefaultsKey)
    }

    public static func signOut() {
        KaiKeychain.deleteApiKey(for: accessKeychainName)
        KaiKeychain.deleteApiKey(for: refreshKeychainName)
        UserDefaults.standard.removeObject(forKey: expiryDefaultsKey)
    }

    /// Returns a usable access token, refreshing it when it expires within a minute.
    public static func validAccessToken(session: URLSession = .shared, now: Date = Date()) async throws -> String {
        guard let refresh = KaiKeychain.apiKey(for: refreshKeychainName) else { throw AuthError.notSignedIn }
        let expiry = UserDefaults.standard.double(forKey: expiryDefaultsKey)
        if let access = KaiKeychain.apiKey(for: accessKeychainName), expiry > now.addingTimeInterval(60).timeIntervalSince1970 {
            return access
        }
        guard !clientID.isEmpty else { throw AuthError.noClientID }
        let (data, _) = try await session.data(for: refreshRequest(clientID: clientID, refreshToken: refresh))
        let tokens = try parseTokens(data, now: now)
        store(tokens)
        return tokens.accessToken
    }
}
