import AppKit

/// Manages a borderless, transparent, non-activating, click-through NSPanel
/// pinned to the bottom-right of the active screen. It hosts an animated GIF of
/// the posture pet — the character walks in from the right, stands, and says
/// "sit straight" (all of that motion and text lives inside the GIF itself).
///
/// The panel never steals focus and passes clicks through so it doesn't block
/// whatever is behind it. Each `show()` reloads the GIF so the walk-in replays
/// from its first frame.
@MainActor
final class PetOverlayWindowController {
    private var panel: NSPanel?
    private var imageView: NSImageView?
    private var isPresented = false
    private let margin: CGFloat = 24
    private let gifAspect: CGFloat = 1280.0 / 720.0   // GIF is 1280x720
    private let maxHeight: CGFloat = 360

    func show() {
        let panel = ensurePanel()
        layout(panel)

        // Reload a fresh NSImage so the animation restarts from frame 0 (the
        // walk-in) every time the pet reappears.
        if let url = Bundle.main.url(forResource: "posturebuddy", withExtension: "gif"),
           let image = NSImage(contentsOf: url) {
            imageView?.image = image
            imageView?.animates = true
        }

        isPresented = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, isPresented else { return }
        isPresented = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPresented else { return }
                self.panel?.orderOut(nil)
                self.imageView?.image = nil   // stop animating while hidden
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: maxHeight * gifAspect, height: maxHeight),
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let iv = NSImageView(frame: NSRect(origin: .zero, size: panel.frame.size))
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        iv.autoresizingMask = [.width, .height]
        panel.contentView = iv
        self.imageView = iv
        self.panel = panel
        return panel
    }

    private func layout(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let height = min(maxHeight, vf.height * 0.5)
        let width = height * gifAspect
        let origin = NSPoint(x: vf.maxX - width - margin, y: vf.minY + margin)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
    }
}
