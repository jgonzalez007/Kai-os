//
//  KaiNotchPreferences.swift
//  Kai OS macOS
//

import Foundation

enum KaiNotchPreferences {
    static let enabledKey = "kai.notch.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}
