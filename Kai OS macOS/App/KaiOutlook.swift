//
//  KaiOutlook.swift
//  Kai OS macOS
//
//  Outlook Calendar: sign-in and the AppState glue. Read-only. The request and
//  parsing code lives in KaiLocalData and is covered by KaiChecksTests.
//

import AppKit
import AuthenticationServices
import Foundation
import KaiLocalData

/// Runs the Microsoft sign-in page in the system's secure web session.
@MainActor
final class KaiMicrosoftSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }

    func signIn(clientID: String) async throws {
        let verifier = KaiMicrosoftAuth.makeVerifier()
        let state = UUID().uuidString
        guard let url = KaiMicrosoftAuth.authorizeURL(
            clientID: clientID, challenge: KaiMicrosoftAuth.challenge(for: verifier), state: state
        ) else { throw KaiMicrosoftAuth.AuthError.badResponse }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: KaiMicrosoftAuth.callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? KaiMicrosoftAuth.AuthError.badResponse) }
            }
            session.presentationContextProvider = self
            // A fresh session each time, so the user can pick the account they want.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() { continuation.resume(throwing: KaiMicrosoftAuth.AuthError.badResponse) }
        }
        session = nil

        let code = try KaiMicrosoftAuth.authorizationCode(from: callback, expectedState: state)
        let (data, _) = try await URLSession.shared.data(
            for: KaiMicrosoftAuth.codeExchangeRequest(clientID: clientID, code: code, verifier: verifier)
        )
        KaiMicrosoftAuth.store(try KaiMicrosoftAuth.parseTokens(data))
    }
}

extension AppState {
    func connectOutlook() {
        let clientID = outlookClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            outlookState = .failed("Enter your Microsoft application (client) ID first.")
            return
        }
        KaiMicrosoftAuth.clientID = clientID
        outlookState = .loading
        Task {
            do {
                try await KaiMicrosoftSignIn().signIn(clientID: clientID)
                outlookConnected = true
                outlookState = .connected
                refreshCalendar()
            } catch {
                outlookState = .failed(error.localizedDescription)
            }
        }
    }

    func disconnectOutlook() {
        KaiMicrosoftAuth.signOut()
        outlookConnected = false
        outlookState = .disconnected
        refreshCalendar()
    }

    /// Outlook events for a window, or an empty list and a visible error state if the fetch fails.
    func outlookEvents(from start: Date, to end: Date) async -> [KaiCalendarItem] {
        guard outlookConnected else { return [] }
        do {
            let events = try await KaiOutlookCalendarSource.events(from: start, to: end)
            outlookState = .connected
            return events
        } catch {
            outlookState = .failed("Outlook: \(error.localizedDescription)")
            return []
        }
    }
}
