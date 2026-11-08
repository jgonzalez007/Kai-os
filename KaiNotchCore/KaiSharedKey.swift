//
//  KaiSharedKey.swift
//  Kai NotchCore
//
//  The one modifier key that drives the notch: tap to open, hold to talk, double tap to draft a reply.
//

import Foundation

public enum KaiSharedKey: String, CaseIterable, Sendable {
    case rightCommand, rightOption, rightControl, rightShift

    public static let defaultsKey = "kai.sidekick.sharedKey"
    public static let `default` = KaiSharedKey.rightCommand

    public var title: String {
        switch self {
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        case .rightControl: return "Right ⌃"
        case .rightShift: return "Right ⇧"
        }
    }

    /// The hardware key code of the key.
    public var keyCode: Int {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    /// The device-specific bit in an event's raw modifier flags that says this exact key is down.
    public var deviceMask: UInt {
        switch self {
        case .rightCommand: return 0x10
        case .rightOption: return 0x40
        case .rightControl: return 0x2000
        case .rightShift: return 0x4
        }
    }

    public static func stored(_ defaults: UserDefaults = .standard) -> KaiSharedKey {
        defaults.string(forKey: defaultsKey).flatMap(KaiSharedKey.init(rawValue:)) ?? .default
    }
}
