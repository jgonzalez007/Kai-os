//
//  KaiSpinningLogo.swift
//  Kai OS macOS
//

import SwiftUI

struct KaiSpinningLogo: View {
    var spinning: Bool

    var body: some View {
        TimelineView(.animation(paused: !spinning)) { context in
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .rotationEffect(.degrees(spinning ? context.date.timeIntervalSinceReferenceDate * 180 : 0))
        }
    }
}
