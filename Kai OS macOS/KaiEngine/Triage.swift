//
//  Triage.swift
//  Kai OS macOS
//
//  Summarize and categorize model output
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

/// Triage — processes raw model output into structured, actionable summaries
public final class Triage {
    
    /// Triage a raw inference response
    /// - Parameter response: Raw model output
    /// - Returns: Structured summary with type classification
    public static func triage(_ response: String) -> TriagedResponse {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Classify the response type
        let type: ResponseType
        if trimmed.lowercased().contains("calendar") || trimmed.lowercased().contains("event") {
            type = .calendar
        } else if trimmed.lowercased().contains("email") || trimmed.lowercased().contains("mail") {
            type = .email
        } else if trimmed.lowercased().contains("reminder") || trimmed.lowercased().contains("todo") {
            type = .reminder
        } else if trimmed.lowercased().contains("schedule") || trimmed.lowercased().contains("meeting") {
            type = .schedule
        } else {
            type = .general
        }
        
        return TriagedResponse(
            original: trimmed,
            type: type,
            confidence: classifyConfidence(trimmed),
            actionItems: extractActionItems(trimmed)
        )
    }
    
    /// Classify confidence in the triage result (0.0 - 1.0)
    private static func classifyConfidence(_ text: String) -> Float {
        var score: Float = 0.5
        let words = text.split(separator: " ").map(String.init)
        
        // Heuristic: more specific words = higher confidence
        let specificWords: [String] = ["specifically", "definitely", "must", "should", "recommend", "note"]
        for word in specificWords {
            if words.contains(where: { $0.lowercased() == word }) {
                score += 0.1
            }
        }
        
        return min(score, 1.0)
    }
    
    /// Extract actionable items from text
    private static func extractActionItems(_ text: String) -> [String] {
        var items: [String] = []
        let lines = text.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  trimmed.count > 5,
                  !trimmed.hasPrefix("//") else {
                continue
            }
            items.append(trimmed)
        }
        
        return items
    }
}

/// Type of response produced by the engine
public enum ResponseType: String, CaseIterable {
    case calendar
    case email
    case reminder
    case schedule
    case general
    
    public static let allTypes = Self.allCases.map(\.rawValue)
}

/// Structured triaged response
public struct TriagedResponse {
    public let original: String
    public let type: ResponseType
    public let confidence: Float
    public let actionItems: [String]
}
