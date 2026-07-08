import AppKit
import SwiftUI

/// Manages a borderless, transparent, non-activating NSPanel pinned to the
/// bottom-right of the active screen. Hosts a PetView and never steals focus.
/// The pet slides + fades in/out via NSAnimationContext on the panel itself.
@MainActor
final class PetOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<PetView>?
    private var isPresented = false
    private let size = NSSize(width: 240, height: 220)
    private let margin: CGFloat = 24
    private let animationDuration: TimeInterval = 0.35

    func show(message: String) {
        let panel = ensurePanel()
        hostingView?.rootView = PetView(message: message)
        isPresented = true

        guard let screen = NSScreen.main else {
            panel.orderFrontRegardless()
            return
        }
        let vf = screen.visibleFrame
        let onX = vf.maxX - size.width - margin
        let offX = vf.maxX + margin          // just off the right edge
        let y = vf.minY + margin

        // Start off-screen and transparent, then slide/fade in.
        panel.setFrame(NSRect(x: offX, y: y, width: size.width, height: size.height), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: onX, y: y, width: size.width, height: size.height), display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isPresented else { return }
        isPresented = false

        guard let screen = NSScreen.main else {
            panel.orderOut(nil)
            return
        }
        let vf = screen.visibleFrame
        let offX = vf.maxX + margin
        let y = panel.frame.origin.y

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(NSRect(x: offX, y: y, width: size.width, height: size.height), display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPresented else { return }
                self.panel?.orderOut(nil)
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: PetView(message: ""))
        panel.contentView = hosting
        self.hostingView = hosting
        self.panel = panel
        return panel
    }
}
