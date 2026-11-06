//
//  KaiHoldGesture.swift
//  Kai OS
//
//  Tells a tap of a key from a hold, so chords such as Command-C never count as either.
//  The owner starts a timer on each press and reports it with the press's token.
//

import Foundation

public struct KaiHoldGesture: Sendable {
    public enum Action: Equatable, Sendable {
        case none, toggle, beginHold, endHold, cancelHold
    }

    public static let holdThreshold: TimeInterval = 0.25

    private var pressedAt: TimeInterval?
    private var isHolding = false
    private var currentToken = 0

    public init() {}

    /// Returns a token for the hold timer that belongs to this press.
    public mutating func press(at time: TimeInterval) -> Int {
        currentToken += 1
        pressedAt = time
        isHolding = false
        return currentToken
    }

    public mutating func holdTimerFired(token: Int) -> Action {
        guard token == currentToken, pressedAt != nil, !isHolding else { return .none }
        isHolding = true
        return .beginHold
    }

    /// Another key was used while this one was down.
    public mutating func interrupt() -> Action {
        defer { reset() }
        return isHolding ? .cancelHold : .none
    }

    public mutating func release(at time: TimeInterval) -> Action {
        defer { reset() }
        guard let pressedAt else { return .none }
        if isHolding { return .endHold }
        return time - pressedAt <= Self.holdThreshold ? .toggle : .none
    }

    private mutating func reset() {
        pressedAt = nil
        isHolding = false
    }
}
