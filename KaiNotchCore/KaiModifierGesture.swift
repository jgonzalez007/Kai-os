//
//  KaiModifierGesture.swift
//  Kai OS
//
//  Recognizes a lone tap of a modifier key, so chords such as Command-C never count.
//

import Foundation

public struct KaiModifierGesture: Sendable {
    public static let maximumTapDuration: TimeInterval = 0.25

    private var pressedAt: TimeInterval?

    public init() {}

    public mutating func press(at time: TimeInterval) {
        pressedAt = time
    }

    /// Another key was used while the modifier was down.
    public mutating func interrupt() {
        pressedAt = nil
    }

    /// Returns true when this release completes a tap.
    public mutating func release(at time: TimeInterval) -> Bool {
        defer { pressedAt = nil }
        guard let pressedAt else { return false }
        return time - pressedAt <= Self.maximumTapDuration
    }
}
