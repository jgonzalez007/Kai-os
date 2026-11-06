//
//  KaiHoldGesture.swift
//  Kai OS
//
//  Tells a tap, a double tap and a hold of one key apart, so chords such as Command-C never
//  count as any of them. A single tap can only be confirmed once the double-tap window ends,
//  so the owner runs a timer for each token this reports and hands the token back.
//

import Foundation

public struct KaiHoldGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case none
        /// A first tap: call `tapTimerFired` with this token after `doubleTapWindow`.
        case awaitSecondTap(token: Int)
        case toggle
        case doubleTap
        case beginHold
        case endHold
        case cancelHold
    }

    public static let holdThreshold: TimeInterval = 0.25
    public static let doubleTapWindow: TimeInterval = 0.35

    private var pressedAt: TimeInterval?
    private var isHolding = false
    private var pressToken = 0
    private var lastTapAt: TimeInterval?
    private var tapToken = 0

    public init() {}

    /// Returns a token for the hold timer that belongs to this press.
    public mutating func press(at time: TimeInterval) -> Int {
        pressToken += 1
        pressedAt = time
        isHolding = false
        return pressToken
    }

    public mutating func holdTimerFired(token: Int) -> Action {
        guard token == pressToken, pressedAt != nil, !isHolding else { return .none }
        isHolding = true
        lastTapAt = nil
        return .beginHold
    }

    public mutating func tapTimerFired(token: Int) -> Action {
        guard token == tapToken, let lastTapAt else { return .none }
        // A second press is already down in time, so its release decides what this was.
        if let pressedAt, pressedAt - lastTapAt <= Self.doubleTapWindow { return .none }
        self.lastTapAt = nil
        return .toggle
    }

    /// Another key was used while this one was down.
    public mutating func interrupt() -> Action {
        let wasHolding = isHolding
        pressedAt = nil
        isHolding = false
        return wasHolding ? .cancelHold : .none
    }

    public mutating func release(at time: TimeInterval) -> Action {
        defer {
            pressedAt = nil
            isHolding = false
        }
        guard let pressedAt else { return .none }
        if isHolding { return .endHold }
        guard time - pressedAt <= Self.holdThreshold else { return .none }
        tapToken += 1
        if let lastTapAt, pressedAt - lastTapAt <= Self.doubleTapWindow {
            self.lastTapAt = nil
            return .doubleTap
        }
        lastTapAt = time
        return .awaitSecondTap(token: tapToken)
    }
}
