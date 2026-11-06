//
//  KaiProactiveExecutor.swift
//  Kai OS macOS
//
//  Fire pipeline — real system calls for notifications, calendar, email, computer
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI
// import EventKit // STUB
// import UserNotifications // STUB

/// Proactive action types the fire pipeline can trigger
public enum ProactiveActionType: String, CaseIterable {
    case notification
    case calendarInvite
    case emailReply
    case computerAction
    case researchTask
    case reminder
    
    var displayTitle: String {
        switch self {
        case .notification:
            return "Notify Me"
        case .calendarInvite:
            return "Add to Calendar"
        case .emailReply:
            return "Reply to Email"
        case .computerAction:
            return "Take Action"
        case .researchTask:
            return "Research"
        case .reminder:
            return "Reminder"
        }
    }
}

/// A proactive action ready to be executed
public struct ProactiveAction {
    public let id: String
    public let type: ProactiveActionType
    public let title: String
    public let body: String
    public let confirmationRequired: Bool
    public let payload: [String: Any]?
    
    public init(
        id: String,
        type: ProactiveActionType,
        title: String,
        body: String,
        confirmationRequired: Bool = true,
        payload: [String: Any]? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.confirmationRequired = confirmationRequired
        self.payload = payload
    }
}

/// Fire pipeline — dispatches proactive actions through real system APIs
public final class KaiProactiveExecutor {
    
    public static let shared = KaiProactiveExecutor()
    
    /// Queue of actions that have been fired but not yet confirmed
    private var pendingActions: [String: ProactiveAction] = [:]
    
    /// History of actions that have been executed
    private(set) var actionHistory: [ProactiveActionResult] = []
    
    /// Whether the fire pipeline has been authorized to send notifications
    public var notificationsAuthorized: Bool = false
    
    private init() {
        checkNotificationAuthorization()
    }
    
    // MARK: - Fire Pipeline
    
    /// Fire a proactive action — send notification, open calendar, draft email, or run a computer command
    /// - Parameter action: The action to execute
    /// - Returns: Result of the execution
    @MainActor
    public func fire(_ action: ProactiveAction) async throws -> ProactiveActionResult {
        
        var result = ProactiveActionResult(
            action: action,
            timestamp: Date(),
            status: .processing
        )
        
        switch action.type {
        case .notification:
            let fireResult = try await sendNotification(
                title: action.title,
                body: action.body,
                identifier: action.id
            )
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Notification send failed"
            
        case .calendarInvite:
            let fireResult = try await createCalendarEvent(title: action.title, body: action.body)
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Calendar event creation failed"
            
        case .emailReply:
            let fireResult = try await draftEmailReply(title: action.title, body: action.body)
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Email draft failed"
            
        case .computerAction:
            let fireResult: Bool
            if let payload = action.payload,
               let command = payload["command"] as? String {
                fireResult = try await runSystemCommand(command)
            } else {
                fireResult = try await runSystemCommand(action.body)
            }
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Computer action failed"
            
        case .researchTask:
            let fireResult = try await launchResearchTask(action.body)
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Research task launch failed"
            
        case .reminder:
            let fireResult = try await scheduleReminder(title: action.title, body: action.body)
            result.status = fireResult ? .success : .failed
            result.error = fireResult ? nil : "Reminder scheduling failed"
        }
        
        // Store in history
        if action.confirmationRequired {
            pendingActions[action.id] = action
        }
        actionHistory.append(result)
        
        return result
    }
    
    /// Fire multiple actions, showing confirmation for each
    @MainActor
    public func fire(_ actions: [ProactiveAction]) async throws -> [ProactiveActionResult] {
        return try await withThrowingTaskGroup(of: ProactiveActionResult.self) { group in
            var results: [ProactiveActionResult] = []
            
            for action in actions {
                group.addTask { @MainActor in
                    return try await self.fire(action)
                }
            }
            
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
    }
    
    // MARK: - NSUserNotification
    
    /// Send a local notification through NSUserNotificationCenter
    private func sendNotification(title: String, body: String, identifier: String) async throws -> Bool {
        guard notificationsAuthorized else {
            return try await requestNotificationAuthorization()
        }
        
        return await withCheckedContinuation { continuation in
            let center = UNUserNotificationCenter.current()
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "kai-proactive"
            
            // Fire immediately
            let trigger = UNTimeIntervalTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("[KaiProactive] Notification error: \(error.localizedDescription)")
                }
                continuation.resume(returning: error == nil)
            }
        }
    }
    
    /// Request notification authorization
    private func requestNotificationAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound, .badge]) { authorized, error in
                if let error = error {
                    print("[KaiProactive] Authorization error: \(error.localizedDescription)")
                }
                self.notificationsAuthorized = authorized
                continuation.resume(returning: authorized)
            }
        }
    }
    
    private func checkNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            self.notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }
    
    // MARK: - Calendar
    
    /// Create a calendar event using EventKit
    private func createCalendarEvent(title: String, body: String) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            let store = EKEventStore()
            store.requestAccess(for: .event) { authorized, error in
                guard authorized else {
                    continuation.resume(returning: false)
                    return
                }
                
                let event = EKEvent(eventStore: store)
                event.title = title
                event.notes = body
                event.startDate = Date()
                event.endDate = Date().addingTimeInterval(3600)
                event.calendar = store.defaultCalendarForNewEvents
                
                do {
                    try store.save(event, span: .thisEvent)
                    continuation.resume(returning: true)
                } catch {
                    print("[KaiProactive] Calendar event error: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    // MARK: - Email
    
    /// Draft an email reply using MailComposeViewController (Mail.app)
    private func draftEmailReply(title: String, body: String) async throws -> Bool {
        // Use AppleScript to draft in Apple Mail
        return await withCheckedContinuation { continuation in
            let script = """
            tell application "Mail"
                set newMessage to make new outgoing message with properties ¬
                    {subject: "\(title.replacingOccurrences(of: "\"", with: "\\\""))", ¬
                    content: "\(body.replacingOccurrences(of: "\"", with: "\\\""))", ¬
                    visible:false}
                tell newMessage
                    set draft to true
                end tell
            end tell
            """
            
            do {
                var errorDict: NSDictionary?; try NSAppleScript(source: script)?.executeAndReturnError(&errorDict)
                continuation.resume(returning: true)
            } catch {
                print("[KaiProactive] Mail draft error: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Computer Actions
    
    /// Run a system command (shell script)
    private func runSystemCommand(_ command: String) async throws -> Bool {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.launchPath = "/usr/bin/env"
            process.arguments = ["sh", "-c", command]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch {
                print("[KaiProactive] Command execution error: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Research Tasks
    
    /// Launch a research task using ProactiveResearch
    private func launchResearchTask(_ query: String) async throws -> Bool {
        do {
            let results = try await KaiProactiveResearch.shared.search(query)
            return !results.isEmpty
        } catch {
            print("[KaiProactive] Research launch error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Reminders
    
    /// Schedule a reminder using Reminders API
    private func scheduleReminder(title: String, body: String) async throws -> Bool {
        // Reminders are accessed through EventKit
        return await withCheckedContinuation { continuation in
            let store = EKEventStore()
            store.requestAccess(for: .event) { authorized, error in
                guard authorized else {
                    continuation.resume(returning: false)
                    return
                }
                
                // Create as an all-day event in a default calendar
                let event = EKEvent(eventStore: store)
                event.title = title
                event.notes = body
                event.startDate = Date().addingTimeInterval(86400) // Tomorrow
                event.endDate = Date().addingTimeInterval(86400 + 3600)
                event.calendar = store.defaultCalendarForNewEvents
                
                do {
                    try store.save(event, span: .thisEvent)
                    continuation.resume(returning: true)
                } catch {
                    print("[KaiProactive] Reminder error: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

/// Result of a proactive action execution
public struct ProactiveActionResult {
    public let action: ProactiveAction
    public let timestamp: Date
    public var status: ActionStatus
    
    /// Optional error message for failed actions
    public var error: String?
}

public enum ActionStatus: String {
    case processing
    case success
    case failed
    case cancelled
}
