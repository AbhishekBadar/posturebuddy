import AppKit
import SwiftUI

/// Manages a borderless, transparent, non-activating NSPanel pinned to the
/// bottom-right of the active screen. Hosts a PetView and never steals focus.
@MainActor
final class PetOverlayWindowController {
    private var panel: NSPanel?
    private var isPresented = false
    private let size = NSSize(width: 240, height: 220)
    private let margin: CGFloat = 24

    func show(message: String) {
        let panel = ensurePanel()
        isPresented = true
        panel.contentView = NSHostingView(
            rootView: PetView(message: message, isPresented: .constant(true))
        )
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        guard let panel, isPresented else { return }
        isPresented = false
        // Slide out, then remove from screen.
        panel.contentView = NSHostingView(
            rootView: PetView(message: "", isPresented: .constant(false))
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.isPresented else { return }
            self.panel?.orderOut(nil)
        }
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
        self.panel = panel
        return panel
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.maxX - size.width - margin,
                             y: vf.minY + margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
