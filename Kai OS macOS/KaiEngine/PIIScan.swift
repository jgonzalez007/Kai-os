//
//  PIIScan.swift
//  Kai OS macOS
//
//  Strip PII before sending to cloud APIs
//  Copyright © 2026 Kai OS Labs. All rights reserved.
//

import Foundation

/// PIIScan — detects and masks personally identifiable information
public final class PIIScan {
    
    public static let shared = PIIScan()
    
    private let patterns: [PIIPattern]
    
    private init() {
        self.patterns = [
            // Email addresses
            PIIPattern(
                regex: #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#,
                type: .email,
                replacement: "[EMAIL]"
            ),
            // Phone numbers (US)
            PIIPattern(
                regex: #"\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}"#,
                type: .phone,
                replacement: "[PHONE]"
            ),
            // SSN
            PIIPattern(
                regex: #"\d{3}-\d{2}-\d{4}"#,
                type: .ssn,
                replacement: "[SSN]"
            ),
            // Credit cards
            PIIPattern(
                regex: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#,
                type: .creditCard,
                replacement: "[CREDIT_CARD]"
            ),
            // Dates of birth
            PIIPattern(
                regex: #"(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},?\s+\d{4}"#,
                type: .dateOfBirth,
                replacement: "[DATE_OF_BIRTH]"
            ),
            // Physical addresses
            PIIPattern(
                regex: #"\d+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*,\s+[A-Z]{2}\s+\d{5}"#,
                type: .address,
                replacement: "[ADDRESS]"
            ),
            // IP addresses
            PIIPattern(
                regex: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
                type: .ipAddress,
                replacement: "[IP_ADDRESS]"
            )
        ]
    }
    
    /// Scan and mask PII in text
    /// - Parameter text: Input text
    /// - Returns: Text with PII replaced by placeholders
    public func scanAndMask(_ text: String) -> (masked: String, piiFound: Bool) {
        var result = text
        var found = false
        
        for pattern in patterns {
            guard let regexPattern = try? NSRegularExpression(
                pattern: pattern.regex,
                options: [.caseInsensitive]
            ) else { continue }
            
            let nsResult = result as NSString
            let nsRange = NSRange(result.startIndex..., in: result)
            if regexPattern.numberOfMatches(in: result, options: [], range: nsRange) > 0 {
                found = true
                result = nsResult.replacingCharacters(in: nsRange, with: pattern.replacement)
            }
        }
        
        return (result, found)
    }
    
    /// Check if text contains PII without masking
    public func hasPII(_ text: String) -> Bool {
        return scanAndMask(text).piiFound
    }
    
    /// Get a summary of what PII was found
    public func getPIISummary(_ text: String) -> [String: Int] {
        var summary: [String: Int] = [:]
        let working = text
        
        for pattern in patterns {
            let regex = try? NSRegularExpression(
                pattern: pattern.regex,
                options: [.caseInsensitive]
            )
            guard let regex = regex else { continue }
            
            let range = NSRange(working.startIndex..., in: working)
            let matches = regex.matches(in: working, options: [], range: range)
            
            if !matches.isEmpty {
                summary[pattern.type.rawValue] = matches.count
            }
        }
        
        return summary
    }
}

/// Type of PII detected
public enum PIIType: String, CaseIterable {
    case email
    case phone
    case ssn
    case creditCard
    case dateOfBirth
    case address
    case ipAddress
    
    public static let allTypes = Self.allCases.map(\.rawValue)
}

/// Pattern for PII detection
public struct PIIPattern {
    let regex: String
    let type: PIIType
    let replacement: String
}
