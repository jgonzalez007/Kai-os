//
//  KaiAppAwareness.swift
//  Kai OS macOS
//
//  App-awareness — detect frontmost application and adapt UI/suggestions
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation
import SwiftUI
import AppKit
import Observation

/// Detected application category for adaptive UI
public enum AppCategory: String {
    case browser = "Browser"
    case mail = "Mail"
    case calendar = "Calendar"
    case messaging = "Messaging"
    case notes = "Notes"
    case codeEditor = "Code Editor"
    case finder = "Finder"
    case other = "Other"
    
    /// Suggested actions for this app category
    var suggestedActions: [String] {
        switch self {
        case .browser:
            return ["Summarize page", "Find related notes", "Search knowledge base", "Save to Kai"]
        case .mail:
            return ["Draft reply", "Summarize thread", "Extract tasks", "Schedule follow-up"]
        case .calendar:
            return ["Check conflicts", "Find free time", "Suggest agenda", "Nearby events"]
        case .messaging:
            return ["Smart reply", "Summarize thread", "Extract contacts", "Draft response"]
        case .notes:
            return ["Add context", "Link to knowledge", "Find related notes", "Summarize"]
        case .codeEditor:
            return ["Explain code", "Find docs", "Generate tests", "Check dependencies"]
        case .finder:
            return ["Organize files", "Find duplicates", "Tag files", "Move to knowledge"]
        case .other:
            return ["What do you need?", "Summarize content", "Extract actions"]
        }
    }
    
    /// Icon name for this category
    var icon: String {
        switch self {
        case .browser: return "globe"
        case .mail: return "envelope"
        case .calendar: return "calendar"
        case .messaging: return "bubble"
        case .notes: return "doc"
        case .codeEditor: return "square.grid.2x2"
        case .finder: return "folder"
        case .other: return "app"
        }
    }
}

/// App-awareness engine — detects the frontmost application and provides adaptive UI/suggestions
public final class KaiAppAwareness: Observable {
    
    public static let shared = KaiAppAwareness()
    
    /// The currently detected frontmost application bundle ID
    public private(set) var frontmostAppBundleID: String?
    
    /// The currently detected application category
    public private(set) var frontmostAppCategory: AppCategory = .other
    
    /// The currently detected application display name
    public private(set) var frontmostAppName: String?
    
    /// Whether app-awareness is actively monitoring
    public var isMonitoring = false
    
    /// Adaptive suggestions for the current app context
    public var adaptiveSuggestions: [String] {
        return frontmostAppCategory.suggestedActions
    }
    
    /// The adaptive UI mode for the current app context
    public var uiMode: AppAwarenessUI {
        return frontmostAppCategory.toUI()
    }
    
    /// Store for app usage statistics (most used apps, patterns)
    public private(set) var appUsageStats = [String: AppUsageEntry]()
    
    private var observation: NSKeyValueObservation?
    private var lastScanTime: Date?
    private let scanInterval: TimeInterval = 1.0 // 1 second between scans
    
    private init() {}
    
    /// Start monitoring the frontmost application
    public func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        // Observe frontmost application changes
        observation = NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.detectFrontmostApp()
            }
        }
        
        // Also do an initial scan
        DispatchQueue.main.async {
            self.detectFrontmostApp()
        }
    }
    
    /// Stop monitoring the frontmost application
    public func stopMonitoring() {
        isMonitoring = false
        observation = nil
    }
    
    /// Detect the currently frontmost application
    @MainActor
    private func detectFrontmostApp() {
        guard isMonitoring else { return }
        
        guard let app = NSWorkspace.shared.frontmostApplication else {
            // No frontmost app (maybe desktop is focused)
            guard frontmostAppBundleID != nil else { return }
            frontmostAppBundleID = nil
            frontmostAppName = nil
            frontmostAppCategory = .other
            frontmostAppBundleID = nil
            frontmostAppName = nil
            return
        }
        
        let bundleID = app.bundleIdentifier
        let name = app.localizedName
        
        // Only update if changed
        guard bundleID != frontmostAppBundleID else { return }
        
        frontmostAppBundleID = bundleID
        frontmostAppName = name
        
        // Classify the app
        frontmostAppCategory = classifyApp(bundleID: bundleID ?? "", name: name ?? "")
        
        // Track usage
        trackAppUsage(bundleID: bundleID ?? "")
    }
    
    /// Classify an app bundle ID into a category
    public func classifyApp(bundleID: String, name: String) -> AppCategory {
        // Browser detection
        let browserIDs = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edge",
            "com.apple.Safari.WebExtension"
        ]
        if browserIDs.contains(bundleID) { return .browser }
        
        // Mail detection
        let mailIDs = [
            "com.apple.Mail",
            "com.microsoft.Outlook",
            "com.google.GoogleMail"
        ]
        if mailIDs.contains(bundleID) { return .mail }
        
        // Calendar detection
        let calendarIDs = [
            "com.apple.iCal",
            "com.apple.Reminders",
            "com.microsoft.Outlook"
        ]
        if calendarIDs.contains(bundleID) { return .calendar }
        
        // Messaging detection
        let messagingIDs = [
            "com.apple.MobileSMS",
            "com.facebook Messenger",
            "com.google.Chrome",
            "com.microsoft.Teams"
        ]
        if messagingIDs.contains(bundleID) { return .messaging }
        
        // Notes detection
        let notesIDs = [
            "com.apple.Notes",
            "com.evernote.Evernote",
            "com.microsoft.onenote"
        ]
        if notesIDs.contains(bundleID) { return .notes }
        
        // Code editor detection
        let codeIDs = [
            "com.apple.dt.Xcode",
            "com.github.codespaces",
            "com.microsoft.VSCode",
            "com.sublimetext.4",
            "com.barebones.textpattern"
        ]
        if codeIDs.contains(bundleID) { return .codeEditor }
        
        // Finder
        if bundleID == "com.apple.Finder" { return .finder }
        
        return .other
    }
    
    /// Track app usage for adaptive suggestions
    private func trackAppUsage(bundleID: String) {
        if let existing = appUsageStats[bundleID] {
            appUsageStats[bundleID] = AppUsageEntry(
                bundleID: bundleID,
                usageCount: existing.usageCount + 1,
                lastUsed: Date()
            )
        } else {
            appUsageStats[bundleID] = AppUsageEntry(
                bundleID: bundleID,
                usageCount: 1,
                lastUsed: Date()
            )
        }
    }
    
    /// Get the top N most used apps
    public func topApps(count: Int = 5) -> [(name: String, bundleID: String, count: Int)] {
        return Array(appUsageStats.values
            .sorted { $0.usageCount > $1.usageCount }
            .prefix(count))
            .map { ($0.bundleID, $0.bundleID, $0.usageCount) }
    }
}

/// UI mode for the current app context
public enum AppAwarenessUI: String {
    case adaptiveCard = "Adaptive Card"
    case smartActions = "Smart Actions"
    case contextualHelp = "Contextual Help"
    case researchPanel = "Research Panel"
    case defaultMode = "Default"
    
    /// Map an app category to the best UI mode
    public static func fromCategory(_ category: AppCategory) -> AppAwarenessUI {
        switch category {
        case .browser: return .adaptiveCard
        case .mail: return .smartActions
        case .calendar: return .contextualHelp
        case .messaging: return .smartActions
        case .notes: return .researchPanel
        case .codeEditor: return .contextualHelp
        case .finder: return .adaptiveCard
        case .other: return .defaultMode
        }
    }
}

/// App category extension for UI mode
extension AppCategory {
    func toUI() -> AppAwarenessUI {
        return .fromCategory(self)
    }
}

/// Usage entry for tracking app interaction patterns
public struct AppUsageEntry {
    public let bundleID: String
    public let usageCount: Int
    public let lastUsed: Date
}
