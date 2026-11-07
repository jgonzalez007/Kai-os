//
//  KaiAgentOverlay.swift
//  Kai OS macOS
//
//  The floating panel that shows what the agent is doing, asks for approval and has the Stop
//  button, plus a ring that marks where it clicks. It is a non-activating panel, so using it
//  never brings Kai in front of the app being operated. It is left out of the agent's screenshots.
//

import AppKit
import KaiAgent
import SwiftUI

@MainActor
final class KaiAgentOverlay {
    private let controller: KaiAgentController
    private var panel: NSPanel?
    private var hosting: NSHostingView<KaiAgentBanner>?
    private var ring: NSWindow?

    init(controller: KaiAgentController) {
        self.controller = controller
    }

    func show() {
        let view = NSHostingView(rootView: KaiAgentBanner(controller: controller))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hosting = view
        self.panel = panel
        refreshSize()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        ring?.orderOut(nil)
        panel = nil
        ring = nil
        hosting = nil
    }

    /// The panel grows when it has an approval to show.
    func refreshSize() {
        guard let panel, let hosting, let screen = NSScreen.screens.first else { return }
        DispatchQueue.main.async {
            let size = hosting.fittingSize
            let width = max(size.width, 460)
            let frame = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - size.height - 40, width: width, height: size.height)
            panel.setFrame(frame, display: true)
        }
    }

    /// The panel's area in the coordinates mouse events use (origin at the top left of the main display).
    func protectedFramesInDisplayCoordinates() -> [CGRect] {
        guard let panel, let primary = NSScreen.screens.first else { return [] }
        let frame = panel.frame
        return [CGRect(x: frame.minX, y: primary.frame.height - frame.maxY, width: frame.width, height: frame.height)]
    }

    /// A ring that appears where the agent just clicked, then fades.
    func showTarget(_ point: KaiPlacedPoint) {
        guard let primary = NSScreen.screens.first else { return }
        let size: CGFloat = 44
        let origin = NSPoint(x: point.x - size / 2, y: primary.frame.height - point.y - size / 2)
        let window = ring ?? NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: size, height: size)),
                                      styleMask: .borderless, backing: .buffered, defer: false)
        if ring == nil {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.level = .screenSaver
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
            view.wantsLayer = true
            view.layer?.cornerRadius = size / 2
            view.layer?.borderWidth = 3
            view.layer?.borderColor = NSColor.systemPurple.cgColor
            view.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.18).cgColor
            window.contentView = view
            ring = window
        }
        window.setFrameOrigin(origin)
        window.alphaValue = 1
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            window.animator().alphaValue = 0
        }
    }
}

struct KaiAgentBanner: View {
    @ObservedObject var controller: KaiAgentController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.motionlines").foregroundStyle(.purple)
                Text("Kai is working").font(.headline)
                Spacer()
                Text("Press Esc to stop").font(.caption).foregroundStyle(.secondary)
                Button("Stop") { controller.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .tint(.red)
            }
            Text(controller.statusLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let request = controller.pending {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow this?").font(.subheadline.weight(.semibold))
                    Text(request.summary).font(.callout)
                    if let app = request.application {
                        Text("In: \(app)").font(.caption).foregroundStyle(.secondary)
                    }
                    if request.reason != request.summary {
                        Text(request.reason).font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Approve") { controller.resolve(true) }
                            .buttonStyle(.borderedProminent)
                        Button("Decline") { controller.resolve(false) }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.6), lineWidth: 1.5))
    }
}
