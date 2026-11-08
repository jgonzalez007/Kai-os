//
//  KaiMotion.swift
//  Kai OS macOS
//
//  Small animated effects. All of them check the "Animated effects" switch in Settings,
//  and with it off every view falls back to the plain look from before.
//

import SwiftUI

enum KaiMotion {
    static let key = "kai.motion"
    static var enabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Text with a soft highlight that sweeps across it, for "working" states.
struct KaiShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: 1.5)) / 1.5 * 1.6 - 0.3
            Text(text)
                .font(.caption)
                .foregroundStyle(LinearGradient(
                    colors: [.white.opacity(0.4), .white, .white.opacity(0.4)],
                    startPoint: UnitPoint(x: phase - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: phase + 0.3, y: 0.5)
                ))
        }
    }
}

/// The "Working" pill: shimmering label, a few twinkling sparks, in a soft capsule.
struct KaiWorkingPill: View {
    var body: some View {
        KaiShimmerText(text: "Working")
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay { sparks }
    }

    private var sparks: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ForEach(0..<3, id: \.self) { i in
                    let seed = Double(i) * 2.1
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 2.5, height: 2.5)
                        .opacity(0.35 + 0.65 * abs(sin(t * 2.2 + seed)))
                        .position(
                            x: geo.size.width * (0.2 + 0.3 * Double(i)),
                            y: geo.size.height * 0.5 + sin(t * 1.7 + seed) * geo.size.height * 0.7
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Shows a streaming reply a few characters at a time, with the newest ones fading in.
/// A reply that is already complete shows in full at once.
struct KaiRevealText: View {
    let full: AttributedString
    @State private var shown: Int

    init(text full: AttributedString, streaming: Bool) {
        self.full = full
        _shown = State(initialValue: streaming ? 0 : Int.max)
    }

    private var total: Int { full.characters.count }

    private var visible: AttributedString {
        let count = min(shown, total)
        if count >= total { return full }
        let end = full.characters.index(full.startIndex, offsetBy: count)
        var head = AttributedString(full[full.startIndex..<end])
        let fadeStart = head.characters.index(head.endIndex, offsetBy: -min(14, count))
        head[fadeStart..<head.endIndex].foregroundColor = Color.gray.opacity(0.55)
        return head
    }

    var body: some View {
        Text(visible)
            .task(id: total) {
                while shown < total {
                    let backlog = total - shown
                    shown += max(1, backlog / 14)
                    try? await Task.sleep(for: .milliseconds(28))
                }
            }
    }
}
